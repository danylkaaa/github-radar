import Foundation

public enum CI: String, Codable, Sendable {
    case passed, failed, running, none

    public init(state: String?) {
        switch state {
        case "SUCCESS": self = .passed
        case "FAILURE", "ERROR": self = .failed
        case "PENDING", "EXPECTED": self = .running
        default: self = .none
        }
    }

    public var label: String {
        switch self {
        case .passed: "CI passed"
        case .failed: "CI failed"
        case .running: "CI running"
        case .none: "No CI"
        }
    }

    var finished: Bool { self == .passed || self == .failed }
}

public struct Activity: Codable, Hashable, Sendable {
    public var commits: Int
    public var oid: String
    public var comments: Int
    public var threads: Int
    public var reviews: Int
    public var ci: CI
}

public struct SeenEntry: Codable, Sendable {
    public var activity: Activity
    /// Last time the PR was in a fetch; old entries are pruned by it.
    public var at: Date
    /// New activity was flagged and the viewer has not opened the PR since.
    public var pending: Bool
    /// Up to this time the viewer has seen the PR; later comments by others count as new.
    public var seenAt: Date

    public init(activity: Activity, at: Date, pending: Bool = false, seenAt: Date? = nil) {
        self.activity = activity
        self.at = at
        self.pending = pending
        self.seenAt = seenAt ?? at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = try c.decode(Activity.self, forKey: .activity)
        at = try c.decode(Date.self, forKey: .at)
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        seenAt = try c.decodeIfPresent(Date.self, forKey: .seenAt) ?? at
    }
}

public struct Comment: Hashable, Sendable, Identifiable {
    public var id: String
    public var author: String
    public var avatarURL: URL?
    public var body: String
    public var createdAt: Date
    public var url: URL?
    /// Made by the viewer or a bot: never counted as new.
    public var ownOrBot: Bool
    public var isNew = false

    public init(author: String, avatarURL: URL? = nil, body: String, createdAt: Date, url: URL? = nil, ownOrBot: Bool = false) {
        id = url?.absoluteString ?? "\(author)@\(createdAt.timeIntervalSince1970)"
        self.author = author
        self.avatarURL = avatarURL
        self.body = body
        self.createdAt = createdAt
        self.url = url
        self.ownOrBot = ownOrBot
    }
}

public struct ReviewThread: Hashable, Sendable, Identifiable {
    public var path: String
    public var line: Int?
    public var isResolved: Bool
    /// The latest comments of the thread; `totalCount` is the full number.
    public var comments: [Comment]
    public var totalCount: Int
    public var id: String { "\(path):\(line ?? 0):\(comments.first?.id ?? "")" }

    public init(path: String, line: Int?, isResolved: Bool, comments: [Comment], totalCount: Int) {
        self.path = path
        self.line = line
        self.isResolved = isResolved
        self.comments = comments
        self.totalCount = totalCount
    }
}

public struct Reviewer: Hashable, Sendable, Identifiable {
    public enum State: Int, Sendable, Comparable {
        case changesRequested, approved, commented, requested

        public static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .changesRequested: "Requested changes"
            case .approved: "Approved"
            case .commented: "Commented"
            case .requested: "Review requested"
            }
        }
    }

    public var login: String
    public var avatarURL: URL?
    public var state: State
    public var at: Date?
    /// The person's or team's page.
    public var profileURL: URL?
    /// The review itself, for approvals and change requests.
    public var reviewURL: URL?
    public var id: String { login }

    public init(login: String, avatarURL: URL? = nil, state: State, at: Date? = nil,
                profileURL: URL? = nil, reviewURL: URL? = nil) {
        self.login = login
        self.avatarURL = avatarURL
        self.state = state
        self.at = at
        self.profileURL = profileURL ?? URL(string: "https://github.com/\(login)")
        self.reviewURL = reviewURL
    }
}

public typealias SeenMap = [String: SeenEntry]

public struct Check: Hashable, Sendable, Identifiable {
    public enum State: Int, Sendable, Comparable {
        // order: what needs attention first
        case failed, running, passed, skipped

        public static func < (a: State, b: State) -> Bool { a.rawValue < b.rawValue }
    }

    public var name: String
    public var state: State
    public var url: URL?
    public var duration: TimeInterval?
    public var id: String { name }

    public init(name: String, state: State, url: URL? = nil, duration: TimeInterval? = nil) {
        self.name = name
        self.state = state
        self.url = url
        self.duration = duration
    }

    init(_ raw: RawCheck) {
        name = raw.name
        switch (raw.status, raw.conclusion) {
        case (let status?, _) where status != "COMPLETED": state = .running
        case (_, "SUCCESS"?): state = .passed
        case (_, "PENDING"?), (_, "EXPECTED"?): state = .running
        case (_, "SKIPPED"?), (_, "NEUTRAL"?), (_, "STALE"?): state = .skipped
        default: state = .failed
        }
        url = raw.url.flatMap(URL.init(string:))
        if let start = raw.startedAt.flatMap(isoFormatter.date(from:)) {
            duration = (raw.completedAt.flatMap(isoFormatter.date(from:)) ?? .now).timeIntervalSince(start)
        }
    }
}

public func formatDuration(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded())
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m \(s % 60)s" }
    return "\(s / 3600)h \(s % 3600 / 60)m"
}

public struct CommitInfo: Hashable, Sendable, Identifiable {
    public var oid: String
    public var message: String
    public var author: String
    public var date: Date?
    public var id: String { oid }

    public init(oid: String, message: String, author: String, date: Date?) {
        self.oid = oid
        self.message = message
        self.author = author
        self.date = date
    }
}

public struct Participant: Hashable, Sendable {
    public var login: String
    public var avatarURL: URL?
    public var profileURL: URL? { URL(string: "https://github.com/\(login)") }

    public init(login: String, avatarURL: URL? = nil) {
        self.login = login
        self.avatarURL = avatarURL
    }
}

public struct PullRequest: Identifiable, Hashable, Sendable {
    public var id: String
    public var number: Int
    public var title: String
    public var url: URL
    public var repo: String
    public var author: String
    /// Opened by the viewer.
    public var mine: Bool
    public var isDraft: Bool
    public var updatedAt: Date
    public var ci: CI
    /// Checks of the head commit, failed first; `checkCount` is the full number.
    public var checks: [Check]
    public var checkCount: Int
    public var approvals: Int
    public var changesRequested: Bool
    public var reviewers: Int
    public var comments: Int
    /// Conversation comments (latest 10) and review threads (latest 20).
    public var conversation: [Comment]
    public var threads: [ReviewThread]
    /// Comments by others since the viewer last saw the PR.
    public var newComments: Int
    /// Who approved, asked for changes, commented, or is asked to review.
    public var reviewerList: [Reviewer]
    public var ready: Bool
    public var activity: Activity
    /// Whether the latest comment, review thread and review came from the viewer or a bot (not news for the viewer).
    public var lastCommentOwnOrBot: Bool
    public var lastThreadOwnOrBot: Bool
    public var lastReviewOwnOrBot: Bool
    public var reviewDecision: String?
    /// People on the PR, the viewer first when present, at most 8; `participantCount` is the full number.
    public var participants: [Participant]
    public var participantCount: Int
    public var viewer: String

    /// Participants without the viewer, unless `includeViewer`.
    public func people(includeViewer: Bool) -> (shown: [Participant], total: Int) {
        if includeViewer { return (participants, participantCount) }
        let others = participants.filter { $0.login != viewer }
        return (others, participantCount - (participants.count - others.count))
    }
    public var isNew: Bool
    /// What changed since the viewer last looked; empty for a PR the viewer never saw.
    public var changes: Set<Change> = []
    /// The latest commit: first line of its message, author and time.
    public var commitMessage = ""
    public var commitAuthor = ""
    public var commitDate: Date?
    /// The latest commits, newest first, at most 5.
    public var recentCommits: [CommitInfo] = []
    public var additions = 0
    public var deletions = 0
    public var changedFiles = 0

    /// Marks every comment new or not by `seenAt`, and counts the new ones.
    public mutating func markComments(newAfter seenAt: Date?) {
        func mark(_ c: inout Comment) { c.isNew = seenAt.map { !c.ownOrBot && c.createdAt > $0 } ?? false }
        for i in conversation.indices { mark(&conversation[i]) }
        for t in threads.indices { for i in threads[t].comments.indices { mark(&threads[t].comments[i]) } }
        newComments = conversation.filter(\.isNew).count + threads.flatMap(\.comments).filter(\.isNew).count
    }

    public var org: String { String(repo.split(separator: "/").first ?? "") }
    public var repoName: String { String(repo.split(separator: "/").last ?? "") }

    public var reviewLabel: String {
        if changesRequested { return "Changes requested" }
        if approvals > 0 {
            return reviewDecision == "REVIEW_REQUIRED" ? "Approved (\(approvals)), needs more" : "Approved (\(approvals))"
        }
        return "No reviews"
    }
}

/// How urgent a PR's new activity is; the menu bar dot shows the most urgent one.
public enum Attention: Int, Comparable, Sendable {
    /// Your PR needs a fix: CI failed or changes were requested.
    case fix
    /// Something waits: CI is running, or the PR waits for your review.
    case waiting
    /// Other news, e.g. comments.
    case activity
    /// Your PR is approved or ready to merge.
    case good

    public static func < (a: Attention, b: Attention) -> Bool { a.rawValue < b.rawValue }

    public var label: String {
        switch self {
        case .fix: "needs a fix"
        case .waiting: "waiting"
        case .activity: "new activity"
        case .good: "approved or ready"
        }
    }
}

extension PullRequest {
    public var attention: Attention {
        if mine && (ci == .failed || changesRequested) { return .fix }
        if ci == .running || !mine { return .waiting }
        if mine && (ready || approvals > 0) { return .good }
        return .activity
    }
}

public struct Snapshot: Sendable {
    public var review: [PullRequest]
    /// All open PRs of the viewer, ready ones included.
    public var mine: [PullRequest]
    public var warnings: [String]

    public var ready: [PullRequest] { mine.filter(\.ready) }
    public var all: [PullRequest] { review + mine }

    public init(review: [PullRequest], mine: [PullRequest], warnings: [String]) {
        self.review = review
        self.mine = mine
        self.warnings = warnings
    }
}

private func isHuman(_ author: RawAuthor?, prAuthor: String) -> Bool {
    guard let author else { return false }
    return author.typename != "Bot" && !author.login.hasSuffix("[bot]") && author.login != prAuthor
}

private func ownOrBot(_ author: RawAuthor?, viewer: String) -> Bool {
    guard let author else { return false }
    return author.login == viewer || author.typename == "Bot" || author.login.hasSuffix("[bot]")
}

// UNKNOWN: GitHub has not computed mergeability yet (right after a push)
private let mergeableStates: Set<String> = ["CLEAN", "UNSTABLE", "HAS_HOOKS"]

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

public func makePullRequest(_ raw: RawPullRequest, viewer: String) -> PullRequest {
    let prAuthor = raw.author?.login ?? ""
    let opinions = raw.latestOpinionatedReviews.nodes.filter { isHuman($0.author, prAuthor: prAuthor) }
    var reviewers = Set(opinions.compactMap { $0.author?.login })
    for node in raw.reviews.nodes where isHuman(node.author, prAuthor: prAuthor) {
        reviewers.insert(node.author!.login)
    }
    let approvals = opinions.filter { $0.state == "APPROVED" }.count
    let changesRequested = opinions.contains { $0.state == "CHANGES_REQUESTED" }
    let head = raw.commits.nodes.first?.commit
    let ci = CI(state: head?.statusCheckRollup?.state)
    let comment = { (c: RawComment) in
        Comment(
            author: c.author?.login ?? "ghost",
            avatarURL: c.author?.avatarUrl.flatMap(URL.init(string:)),
            body: c.bodyText.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: isoFormatter.date(from: c.createdAt) ?? .distantPast,
            url: c.url.flatMap(URL.init(string:)),
            ownOrBot: ownOrBot(c.author, viewer: viewer)
        )
    }
    let threads = raw.reviewThreads.nodes.map {
        ReviewThread(path: $0.path, line: $0.line, isResolved: $0.isResolved,
                     comments: $0.comments.nodes.map(comment), totalCount: $0.comments.totalCount)
    }
    var reviewerList: [Reviewer] = opinions.compactMap { review in
        guard let author = review.author else { return nil }
        return Reviewer(login: author.login, avatarURL: author.avatarUrl.flatMap(URL.init(string:)),
                        state: review.state == "APPROVED" ? .approved : .changesRequested,
                        at: review.submittedAt.flatMap(isoFormatter.date(from:)),
                        reviewURL: review.url.flatMap(URL.init(string:)))
    }
    for node in raw.reviews.nodes where isHuman(node.author, prAuthor: prAuthor) {
        guard let author = node.author, !reviewerList.contains(where: { $0.login == author.login }) else { continue }
        reviewerList.append(Reviewer(login: author.login, avatarURL: author.avatarUrl.flatMap(URL.init(string:)), state: .commented))
    }
    for request in raw.reviewRequests.nodes {
        guard let who = request.requestedReviewer, let login = who.login ?? who.name,
              !reviewerList.contains(where: { $0.login == login }) else { continue }
        reviewerList.append(Reviewer(login: login, avatarURL: who.avatarUrl.flatMap(URL.init(string:)), state: .requested,
                                     profileURL: who.url.flatMap(URL.init(string:))))
    }
    reviewerList.sort { $0.state != $1.state ? $0.state < $1.state : $0.login < $1.login }
    let ready = !raw.isDraft
        && raw.mergeable == "MERGEABLE"
        && mergeableStates.contains(raw.mergeStateStatus)
        && (ci == .passed || ci == .none)
        && !changesRequested
        && (raw.reviewDecision == "APPROVED" || (raw.reviewDecision == nil && approvals > 0))

    var pr = PullRequest(
        id: raw.id,
        number: raw.number,
        title: raw.title,
        url: URL(string: raw.url) ?? URL(string: "https://github.com")!,
        repo: raw.repository.nameWithOwner,
        author: raw.author?.login ?? "ghost",
        mine: prAuthor == viewer,
        isDraft: raw.isDraft,
        updatedAt: isoFormatter.date(from: raw.updatedAt) ?? .distantPast,
        ci: ci,
        checks: (head?.statusCheckRollup?.contexts?.nodes ?? []).compactMap { $0?.value.map(Check.init) }
            .sorted { $0.state != $1.state ? $0.state < $1.state : $0.name < $1.name },
        checkCount: head?.statusCheckRollup?.contexts?.totalCount ?? 0,
        approvals: approvals,
        changesRequested: changesRequested,
        reviewers: reviewers.count,
        comments: raw.comments.totalCount + threads.map(\.totalCount).reduce(0, +),
        conversation: raw.comments.nodes.map(comment),
        threads: threads,
        newComments: 0,
        reviewerList: reviewerList,
        ready: ready,
        activity: Activity(
            commits: raw.commits.totalCount,
            oid: head?.oid ?? "",
            comments: raw.comments.totalCount,
            threads: raw.reviewThreads.totalCount,
            reviews: raw.reviews.totalCount,
            ci: ci
        ),
        lastCommentOwnOrBot: ownOrBot(raw.comments.nodes.last?.author, viewer: viewer),
        lastThreadOwnOrBot: ownOrBot(raw.reviewThreads.nodes.last?.comments.nodes.last?.author, viewer: viewer),
        lastReviewOwnOrBot: ownOrBot(raw.reviews.nodes.last?.author, viewer: viewer),
        reviewDecision: raw.reviewDecision,
        participants: raw.participants.nodes
            .sorted { ($0.login == viewer ? 0 : 1) < ($1.login == viewer ? 0 : 1) }
            .map { Participant(login: $0.login, avatarURL: URL(string: $0.avatarUrl)) },
        participantCount: raw.participants.totalCount,
        viewer: viewer,
        isNew: false
    )
    pr.commitMessage = head?.messageHeadline ?? ""
    pr.commitAuthor = head?.author?.user?.login ?? head?.author?.name ?? ""
    pr.commitDate = head?.committedDate.flatMap(isoFormatter.date(from:))
    pr.recentCommits = raw.recentCommits.nodes.reversed().map {
        CommitInfo(oid: $0.commit.oid, message: $0.commit.messageHeadline,
                   author: $0.commit.author?.user?.login ?? $0.commit.author?.name ?? "",
                   date: isoFormatter.date(from: $0.commit.committedDate))
    }
    pr.additions = raw.additions
    pr.deletions = raw.deletions
    pr.changedFiles = raw.changedFiles
    return pr
}

/// What changed on a PR since the viewer last looked.
public enum Change: String, Sendable {
    case ci, comments, reviews, commits

    public var label: String {
        switch self {
        case .ci: "CI result"
        case .comments: "comments"
        case .reviews: "reviews"
        case .commits: "commits"
        }
    }
}

/// What someone other than the viewer changed since `seen`.
public func changes(_ pr: PullRequest, since seen: Activity) -> Set<Change> {
    let now = pr.activity
    var result: Set<Change> = []
    if now.ci.finished && (now.ci != seen.ci || now.oid != seen.oid) { result.insert(.ci) }
    // a force-push keeps the commit count but changes the head
    if !pr.mine && (now.commits > seen.commits || (!seen.oid.isEmpty && now.oid != seen.oid)) { result.insert(.commits) }
    if (now.comments > seen.comments && !pr.lastCommentOwnOrBot) || (now.threads > seen.threads && !pr.lastThreadOwnOrBot) {
        result.insert(.comments)
    }
    if now.reviews > seen.reviews && !pr.lastReviewOwnOrBot { result.insert(.reviews) }
    return result
}

/// True when something the viewer did not do happened since `seen`.
public func hasNewActivity(_ pr: PullRequest, since seen: Activity) -> Bool {
    !changes(pr, since: seen).isEmpty
}

private let pruneAfter: TimeInterval = 14 * 24 * 60 * 60

/// Marks PRs with new activity and returns the seen map to store.
/// With no stored map (first run) every PR counts as seen, so the first run does not flag everything.
/// Entries of PRs missing from this fetch stay for 14 days, so a PR that drops out for a while is not flagged again.
public func applySeen(_ prs: [PullRequest], stored: SeenMap?, now: Date) -> (prs: [PullRequest], seen: SeenMap) {
    var seen = (stored ?? [:]).filter { now.timeIntervalSince($0.value.at) < pruneAfter }
    let marked = prs.map { pr -> PullRequest in
        var pr = pr
        let previous = stored?[pr.id]
        // stays new until the viewer opens it, even if the viewer acts on GitHub meanwhile
        pr.isNew = stored != nil && (previous.map { $0.pending || hasNewActivity(pr, since: $0.activity) } ?? !pr.mine)
        if !pr.isNew {
            pr.markComments(newAfter: nil)
            seen[pr.id] = SeenEntry(activity: pr.activity, at: now, seenAt: now)
        } else if let previous {
            pr.changes = PRCore.changes(pr, since: previous.activity)
            pr.markComments(newAfter: previous.seenAt)
            seen[pr.id] = SeenEntry(activity: previous.activity, at: now, pending: true, seenAt: previous.seenAt)
        } else {
            // never seen: every comment by others is new
            pr.markComments(newAfter: .distantPast)
        }
        return pr
    }
    return (marked, seen)
}

public func buildSnapshot(_ data: SearchResult, includeDrafts: Bool, stored: SeenMap?, now: Date) -> (snapshot: Snapshot, seen: SeenMap) {
    let keep = { (raw: RawPullRequest) in includeDrafts || !raw.isDraft }
    let review = data.review.filter(keep).map { makePullRequest($0, viewer: data.viewer) }
    let mine = data.mine.filter(keep).map { makePullRequest($0, viewer: data.viewer) }
    let (prs, seen) = applySeen(review + mine, stored: stored, now: now)
    let snapshot = Snapshot(
        review: Array(prs.prefix(review.count)),
        mine: Array(prs.dropFirst(review.count)),
        warnings: data.warnings
    )
    return (snapshot, seen)
}

public func relativeAge(_ date: Date, now: Date) -> String {
    let minutes = max(0, Int((now.timeIntervalSince(date) / 60).rounded()))
    if minutes < 60 { return "\(minutes)m" }
    let hours = Int((Double(minutes) / 60).rounded())
    if hours < 24 { return "\(hours)h" }
    return "\(Int((Double(hours) / 24).rounded()))d"
}

/// Fills the menu bar title template: {review}, {mine}, {ready}, {new}. Other text stays as it is.
public func formatTitle(_ template: String, snapshot: Snapshot, newSymbol: String, hasNew: Bool) -> String {
    template
        .replacingOccurrences(of: "{review}", with: String(snapshot.review.count))
        .replacingOccurrences(of: "{mine}", with: String(snapshot.mine.count))
        .replacingOccurrences(of: "{ready}", with: String(snapshot.ready.count))
        .replacingOccurrences(of: "{new}", with: hasNew ? newSymbol : "")
        .trimmingCharacters(in: .whitespaces)
}
