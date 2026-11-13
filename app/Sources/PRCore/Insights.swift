import Foundation

/// One day of the GitHub contribution calendar.
public struct ContributionDay: Hashable, Sendable, Identifiable {
    public let date: Date
    public let count: Int
    /// 0 (none) to 4 (most), as GitHub's quartiles.
    public let level: Int
    public var id: Date { date }

    public init(date: Date, count: Int, level: Int) {
        self.date = date
        self.count = count
        self.level = level
    }
}

/// A commit by the viewer: when (exact time) and where.
public struct CommitRecord: Sendable {
    public let date: Date
    public let repo: String

    public init(date: Date, repo: String) {
        self.date = date
        self.repo = repo
    }
}

/// A merged PR by the viewer.
public struct MergedPR: Sendable {
    public let repo: String
    public let created: Date
    public let merged: Date

    public var org: String { String(repo.split(separator: "/").first ?? "") }
    public var timeToMerge: TimeInterval { merged.timeIntervalSince(created) }

    public init(repo: String, created: Date, merged: Date) {
        self.repo = repo
        self.created = created
        self.merged = merged
    }
}

public enum InsightsPeriod: Int, CaseIterable, Sendable {
    case week = 7, month = 30, quarter = 90, year = 365

    public var label: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .year: "1 year"
        }
    }
}

public struct Insights: Sendable {
    public let period: InsightsPeriod
    public let commits: [CommitRecord]
    /// Commit search returns at most 1000 commits; true when the period has more.
    public let commitsCapped: Bool
    public let merged: [MergedPR]

    public init(period: InsightsPeriod, commits: [CommitRecord], commitsCapped: Bool, merged: [MergedPR]) {
        self.period = period
        self.commits = commits
        self.commitsCapped = commitsCapped
        self.merged = merged
    }
}

public struct MergeStats: Sendable {
    public let count: Int
    public let average: TimeInterval
    public let median: TimeInterval
}

// MARK: - Pure calculations

/// Commits per hour of the day (0…23) in the given calendar's time zone.
public func hourHistogram(_ dates: [Date], calendar: Calendar = .current) -> [Int] {
    var bins = Array(repeating: 0, count: 24)
    for date in dates { bins[calendar.component(.hour, from: date)] += 1 }
    return bins
}

/// Commits per weekday, Monday first.
public func weekdayHistogram(_ dates: [Date], calendar: Calendar = .current) -> [Int] {
    var bins = Array(repeating: 0, count: 7)
    for date in dates {
        // Calendar weekday: 1 = Sunday … 7 = Saturday
        bins[(calendar.component(.weekday, from: date) + 5) % 7] += 1
    }
    return bins
}

/// Repos by the viewer's commits, most first.
public func topRepos(_ commits: [CommitRecord], limit: Int = 8) -> [(repo: String, commits: Int)] {
    var counts: [String: Int] = [:]
    for commit in commits { counts[commit.repo, default: 0] += 1 }
    let sorted = counts.sorted { a, b in a.value != b.value ? a.value > b.value : a.key < b.key }
    return sorted.prefix(limit).map { (repo: $0.key, commits: $0.value) }
}

public func mergeStats(_ prs: [MergedPR]) -> MergeStats? {
    guard !prs.isEmpty else { return nil }
    let times = prs.map(\.timeToMerge).sorted()
    let middle = times.count / 2
    let median = times.count % 2 == 0 ? (times[middle - 1] + times[middle]) / 2 : times[middle]
    return MergeStats(count: times.count, average: times.reduce(0, +) / Double(times.count), median: median)
}

/// Merge stats per org or repo, most PRs first.
public func mergeStats(_ prs: [MergedPR], by key: (MergedPR) -> String) -> [(key: String, stats: MergeStats)] {
    Dictionary(grouping: prs, by: key)
        .compactMap { name, group in mergeStats(group).map { (key: name, stats: $0) } }
        .sorted { $0.stats.count != $1.stats.count ? $0.stats.count > $1.stats.count : $0.key < $1.key }
}

/// "45m", "3h 20m", "2d 4h".
public func formatSpan(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 48 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
    return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(hours % 24)h"
}

/// Days grouped into GitHub-style week columns (Sunday first); the first column may start mid-week.
public func calendarWeeks(_ days: [ContributionDay], calendar: Calendar = .current) -> [[ContributionDay]] {
    var weeks: [[ContributionDay]] = []
    for day in days.sorted(by: { $0.date < $1.date }) {
        if weeks.isEmpty || calendar.component(.weekday, from: day.date) == 1 {
            weeks.append([day])
        } else {
            weeks[weeks.count - 1].append(day)
        }
    }
    return weeks
}

// MARK: - Fetching

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

private let isoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

extension GitHubClient {
    private static func graphQL(token: String, query: String, variables: [String: Any]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw GitHubError.http(http.statusCode) }
        return data
    }

    /// The login of the token's user.
    public static func fetchViewer(token: String) async throws -> String {
        struct Response: Decodable {
            struct Viewer: Decodable { let login: String }
            struct DataField: Decodable { let viewer: Viewer }
            let data: DataField?
        }
        let data = try await graphQL(token: token, query: "query { viewer { login } }", variables: [:])
        guard let login = try JSONDecoder().decode(Response.self, from: data).data?.viewer.login else {
            throw GitHubError.api("Unknown GitHub user")
        }
        return login
    }

    /// The contribution calendar between two dates; GitHub allows at most one year per call.
    public static func fetchCalendar(token: String, from: Date, to: Date) async throws -> [ContributionDay] {
        struct Response: Decodable {
            struct Day: Decodable { let date: String; let contributionCount: Int; let contributionLevel: String }
            struct Week: Decodable { let contributionDays: [Day] }
            struct Calendar: Decodable { let weeks: [Week] }
            struct Collection: Decodable { let contributionCalendar: Calendar }
            struct Viewer: Decodable { let contributionsCollection: Collection }
            struct DataField: Decodable { let viewer: Viewer }
            let data: DataField?
        }
        let query = """
        query ($from: DateTime!, $to: DateTime!) { viewer { contributionsCollection(from: $from, to: $to) {
          contributionCalendar { weeks { contributionDays { date contributionCount contributionLevel } } }
        } } }
        """
        let data = try await graphQL(token: token, query: query,
                                     variables: ["from": isoFormatter.string(from: from), "to": isoFormatter.string(from: to)])
        guard let body = try JSONDecoder().decode(Response.self, from: data).data else { throw GitHubError.api("No calendar") }
        let levels = ["NONE": 0, "FIRST_QUARTILE": 1, "SECOND_QUARTILE": 2, "THIRD_QUARTILE": 3, "FOURTH_QUARTILE": 4]
        return body.viewer.contributionsCollection.contributionCalendar.weeks.flatMap(\.contributionDays).compactMap { day in
            dayFormatter.date(from: day.date).map { ContributionDay(date: $0, count: day.contributionCount, level: levels[day.contributionLevel] ?? 0) }
        }
    }

    /// The viewer's commits since a date with their exact times, newest first, at most `maxPages` × 100.
    public static func fetchCommits(token: String, login: String, since: Date, maxPages: Int = 10) async throws
        -> (commits: [CommitRecord], capped: Bool) {
        struct Response: Decodable {
            struct Item: Decodable {
                struct Commit: Decodable {
                    struct Person: Decodable { let date: String }
                    let author: Person
                }
                struct Repo: Decodable { let full_name: String }
                let commit: Commit
                let repository: Repo
            }
            let total_count: Int
            let items: [Item]
        }
        var commits: [CommitRecord] = []
        var total = 0
        for page in 1...maxPages {
            var components = URLComponents(string: "https://api.github.com/search/commits")!
            components.queryItems = [
                URLQueryItem(name: "q", value: "author:\(login) author-date:>=\(dayFormatter.string(from: since))"),
                URLQueryItem(name: "sort", value: "author-date"),
                URLQueryItem(name: "order", value: "desc"),
                URLQueryItem(name: "per_page", value: "100"),
                URLQueryItem(name: "page", value: String(page)),
            ]
            var request = URLRequest(url: components.url!, timeoutInterval: 20)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw GitHubError.http(http.statusCode) }
            let body = try JSONDecoder().decode(Response.self, from: data)
            total = body.total_count
            for item in body.items {
                let raw = item.commit.author.date
                if let date = isoFractional.date(from: raw) ?? isoFormatter.date(from: raw) {
                    commits.append(CommitRecord(date: date, repo: item.repository.full_name))
                }
            }
            if body.items.count < 100 || commits.count >= total { break }
        }
        return (commits, total > commits.count)
    }

    /// The viewer's PRs merged since a date, at most `maxPages` × 100.
    public static func fetchMerged(token: String, since: Date, maxPages: Int = 5) async throws -> [MergedPR] {
        struct Response: Decodable {
            struct PageInfo: Decodable { let hasNextPage: Bool; let endCursor: String? }
            struct Node: Decodable {
                struct Repo: Decodable { let nameWithOwner: String }
                let createdAt: String?
                let mergedAt: String?
                let repository: Repo?
            }
            struct Search: Decodable { let pageInfo: PageInfo; let nodes: [Node] }
            struct DataField: Decodable { let search: Search }
            let data: DataField?
        }
        let query = """
        query ($q: String!, $after: String) { search(query: $q, type: ISSUE, first: 100, after: $after) {
          pageInfo { hasNextPage endCursor }
          nodes { ... on PullRequest { createdAt mergedAt repository { nameWithOwner } } }
        } }
        """
        var result: [MergedPR] = []
        var after: String?
        for _ in 0..<maxPages {
            var variables: [String: Any] = ["q": "is:pr author:@me is:merged merged:>=\(dayFormatter.string(from: since))"]
            if let after { variables["after"] = after }
            let data = try await graphQL(token: token, query: query, variables: variables)
            guard let search = try JSONDecoder().decode(Response.self, from: data).data?.search else { break }
            for node in search.nodes {
                guard let repo = node.repository?.nameWithOwner,
                      let created = node.createdAt.flatMap(isoFormatter.date(from:)),
                      let merged = node.mergedAt.flatMap(isoFormatter.date(from:)) else { continue }
                result.append(MergedPR(repo: repo, created: created, merged: merged))
            }
            guard search.pageInfo.hasNextPage, let cursor = search.pageInfo.endCursor else { break }
            after = cursor
        }
        return result
    }
}
