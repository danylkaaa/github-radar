import Foundation


/// Made-up PRs for the layout preview.
public enum Samples {
    public static func prs(now: Date = .now) -> [PullRequest] {
        [
            sample("acme/billing-service", 412, "Add token bucket rate limiter to the public invoices API and document the new limits",
                 author: "jdoe", ci: .passed, comments: 3, minutesAgo: 5, isNew: true,
                   participants: ["jdoe", "tmiller", "mchen", "jlee"], extraParticipants: 2),
            sample("globex/web-app", 97, "Fix login redirect loop on expired sessions",
                 author: "me", mine: true, ci: .failed, changesRequested: true, comments: 1, minutesAgo: 42,
                   participants: ["cnovak"]),
            sample("acme/infra", 23, "Bump base image to the next LTS release",
                 author: "me", mine: true, ci: .passed, approvals: 2, minutesAgo: 240, ready: true),
            sample("globex/payments", 311, "Run integration tests against the staging database",
                   author: "me", mine: true, ci: .running, minutesAgo: 2),
        ]
        .map { make in
            var pr = make(now)
            pr.commitMessage = ["Read bucket size from config", "Keep the session cookie on redirect", "Bump base image",
                                "Point tests at the staging DB"][pr.number % 4]
            pr.commitAuthor = pr.author
            pr.commitDate = pr.updatedAt
            pr.recentCommits = [
                CommitInfo(oid: "3f9c2e1a7b4d", message: pr.commitMessage, author: pr.author, date: pr.updatedAt),
                CommitInfo(oid: "b71d09e4c2aa", message: "Add rate limit middleware", author: pr.author,
                           date: pr.updatedAt.addingTimeInterval(-5400)),
            ]
            pr.additions = 120 + pr.number % 90
            pr.deletions = 14 + pr.number % 30
            pr.changedFiles = 3 + pr.number % 7
            return pr
        }
    }

    private static func sampleComments(_ now: Date, count: Int, newCount: Int) -> [Comment] {
        let texts = ["Looks good overall, two small notes below.", "Can we add a test for the empty case?", "Done, pushed a fix."]
        return (0..<min(count, texts.count)).map { i in
            var c = Comment(author: ["jdoe", "mchen", "jlee"][i], body: texts[i],
                            createdAt: now.addingTimeInterval(Double(i - 3) * 1800))
            c.isNew = i >= min(count, texts.count) - newCount
            return c
        }
    }

    private static func sampleChecks(_ ci: CI) -> [Check] {
        [
            Check(name: "CI / lint", state: ci == .failed ? .failed : .passed, duration: 48),
            Check(name: "CI / unit tests", state: .passed, duration: 192),
            Check(name: "CI / build image", state: ci == .running ? .running : .passed, duration: 311),
            Check(name: "Deploy / preview", state: .skipped),
        ].sorted { $0.state < $1.state }
    }

    private static func sample(
        _ repo: String, _ number: Int, _ title: String,
        author: String, mine: Bool = false, ci: CI, approvals: Int = 0, changesRequested: Bool = false,
        comments: Int = 0, minutesAgo: Double, isNew: Bool = false, ready: Bool = false,
        participants: [String] = [], extraParticipants: Int = 0
    ) -> (Date) -> PullRequest {
        { now in PullRequest(
            id: "\(repo)#\(number)", number: number, title: title, url: URL(string: "https://github.com")!,
            repo: repo, author: author, mine: mine, isDraft: false,
            updatedAt: now.addingTimeInterval(-minutesAgo * 60),
            ci: ci,
            checks: sampleChecks(ci), checkCount: sampleChecks(ci).count,
            approvals: approvals, changesRequested: changesRequested, reviewers: approvals + (changesRequested ? 1 : 0),
            comments: comments,
            conversation: sampleComments(now, count: comments, newCount: isNew ? 1 : 0),
            threads: comments > 1 ? [ReviewThread(path: "src/api/limits.ts", line: 42, isResolved: false, comments: [
                Comment(author: "tmiller", body: "Should the bucket size come from config instead of a constant?",
                        createdAt: now.addingTimeInterval(-3600)),
            ], totalCount: 1)] : [],
            newComments: isNew ? 1 : 0,
            reviewerList: approvals > 0 ? [Reviewer(login: "mchen", state: .approved), Reviewer(login: "jlee", state: .approved)]
                : changesRequested ? [Reviewer(login: "cnovak", state: .changesRequested)]
                : [Reviewer(login: "tmiller", state: .commented), Reviewer(login: "core-team", state: .requested)],
            ready: ready,
            activity: Activity(commits: 1, oid: "3f9c2e1a7b4d", comments: 0, threads: 0, reviews: 0, ci: ci),
            lastCommentOwnOrBot: false, lastThreadOwnOrBot: false, lastReviewOwnOrBot: false,
            reviewDecision: ready ? "APPROVED" : nil,
            participants: participants.map { Participant(login: $0) },
            participantCount: participants.count + extraParticipants,
            viewer: "me",
            isNew: isNew,
            changes: isNew ? [.comments, .ci] : []
        ) }
    }

    // MARK: demo data for screenshots

    /// A year of made-up contributions: quiet weekends, busy weeks, more lately.
    public static func calendar(now: Date = .now) -> [ContributionDay] {
        let calendar = Calendar.current
        var seed: UInt64 = 42
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        return (0..<365).reversed().map { back in
            let date = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -back, to: now)!)
            let weekend = [1, 7].contains(calendar.component(.weekday, from: date))
            let ramp = 1 - Double(back) / 365 * 0.6
            let count = max(0, Int((next() * (weekend ? 6 : 28) * ramp).rounded()) - (next() < 0.18 ? 30 : 0))
            let level = count == 0 ? 0 : count < 6 ? 1 : count < 12 ? 2 : count < 20 ? 3 : 4
            return ContributionDay(date: date, count: count, level: level)
        }
    }

    /// Made-up commits and merged PRs for a period, with a daytime rhythm.
    public static func insights(_ period: InsightsPeriod, now: Date = .now) -> Insights {
        let repos = ["acme/billing-service", "acme/web-app", "globex/infra", "acme/api-gateway", "globex/mobile", "acme/docs"]
        let weights = [0.34, 0.24, 0.16, 0.12, 0.09, 0.05]
        var seed: UInt64 = 7
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 33) / Double(1 << 31)
        }
        func pick() -> String {
            var r = next()
            for (repo, w) in zip(repos, weights) {
                r -= w
                if r <= 0 { return repo }
            }
            return repos[0]
        }
        let days = period.rawValue
        var commits: [CommitRecord] = []
        for day in 0..<days {
            let base = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(day) * 86400))
            let weekday = Calendar.current.component(.weekday, from: base)
            let n = [1, 7].contains(weekday) ? Int(next() * 3) : 3 + Int(next() * 9)
            for _ in 0..<n {
                // most commits between 10:00 and 19:00, a few late
                let hour = next() < 0.85 ? 10 + next() * 9 : 20 + next() * 3
                commits.append(CommitRecord(date: base.addingTimeInterval(hour * 3600), repo: pick()))
            }
        }
        var merged: [MergedPR] = []
        for _ in 0..<max(3, days / 2) {
            let mergedAt = now.addingTimeInterval(-next() * Double(days) * 86400)
            let hours = next() < 0.6 ? next() * 4 : 4 + next() * 60
            merged.append(MergedPR(repo: pick(), created: mergedAt.addingTimeInterval(-hours * 3600), merged: mergedAt))
        }
        return Insights(period: period, commits: commits, commitsCapped: false, merged: merged)
    }
}

