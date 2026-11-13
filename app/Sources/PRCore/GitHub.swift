import Foundation

public struct RawAuthor: Decodable, Sendable {
    public let login: String
    public let typename: String?
    public let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case login, avatarUrl
        case typename = "__typename"
    }

    public init(login: String, typename: String? = nil, avatarUrl: String? = nil) {
        self.login = login
        self.typename = typename
        self.avatarUrl = avatarUrl
    }
}

public struct RawComment: Decodable, Sendable {
    public let author: RawAuthor?
    public let bodyText: String
    public let createdAt: String
    public let url: String?
}

public struct RawPullRequest: Decodable, Sendable {
    public struct Repository: Decodable, Sendable { public let nameWithOwner: String }
    public struct AuthorNode: Decodable, Sendable { public let author: RawAuthor? }
    public struct Comments: Decodable, Sendable {
        public let totalCount: Int
        public let nodes: [RawComment]
    }
    public struct Threads: Decodable, Sendable {
        public struct Thread: Decodable, Sendable {
            public let path: String
            public let line: Int?
            public let isResolved: Bool
            public let comments: Comments
        }
        public let totalCount: Int
        public let nodes: [Thread]
    }
    public struct ReviewRequests: Decodable, Sendable {
        public struct Request: Decodable, Sendable {
            public struct Reviewer: Decodable, Sendable {
                public let login: String?
                public let name: String?
                public let avatarUrl: String?
                public let url: String?
            }
            public let requestedReviewer: Reviewer?
        }
        public let nodes: [Request]
    }
    public struct Commits: Decodable, Sendable {
        public struct Node: Decodable, Sendable {
            public struct Commit: Decodable, Sendable {
                public struct Rollup: Decodable, Sendable {
                    public struct Contexts: Decodable, Sendable {
                        public let totalCount: Int
                        public let nodes: [Failable<RawCheck>?]
                    }
                    public let state: String
                    public let contexts: Contexts?
                }
                public struct CommitAuthor: Decodable, Sendable {
                    public struct User: Decodable, Sendable { public let login: String }
                    public let name: String?
                    public let user: User?
                }
                public let oid: String
                public let messageHeadline: String?
                public let committedDate: String?
                public let author: CommitAuthor?
                public let statusCheckRollup: Rollup?
            }
            public let commit: Commit
        }
        public let totalCount: Int
        public let nodes: [Node]
    }
    public struct Opinions: Decodable, Sendable {
        public struct Review: Decodable, Sendable {
            public let state: String
            public let author: RawAuthor?
            public let submittedAt: String?
            public let url: String?
        }
        public let nodes: [Review]
    }
    public struct Reviews: Decodable, Sendable {
        public let totalCount: Int
        public let nodes: [AuthorNode]
    }

    public let id: String
    public let number: Int
    public let title: String
    public let url: String
    public let isDraft: Bool
    public let updatedAt: String
    public let mergeable: String
    public let mergeStateStatus: String
    public let reviewDecision: String?
    public let repository: Repository
    public let author: RawAuthor?
    public let comments: Comments
    public let reviewThreads: Threads
    public let commits: Commits
    public let latestOpinionatedReviews: Opinions
    public let reviews: Reviews
    public let reviewRequests: ReviewRequests
    public let participants: Participants
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int
    public let recentCommits: RecentCommits

    public struct RecentCommits: Decodable, Sendable {
        public struct Node: Decodable, Sendable {
            public struct Commit: Decodable, Sendable {
                public let oid: String
                public let messageHeadline: String
                public let committedDate: String
                public let author: Commits.Node.Commit.CommitAuthor?
            }
            public let commit: Commit
        }
        public let nodes: [Node]
    }

    public struct Participants: Decodable, Sendable {
        public struct User: Decodable, Sendable {
            public let login: String
            public let avatarUrl: String
        }
        public let totalCount: Int
        public let nodes: [User]
    }
}

public struct SearchResult: Sendable {
    public let viewer: String
    public let mine: [RawPullRequest]
    public let review: [RawPullRequest]
    /// Partial errors, e.g. an org with SAML enforcement hides its PRs.
    public let warnings: [String]
}

public enum GitHubError: LocalizedError {
    case noToken
    case http(Int)
    case api(String)

    public var errorDescription: String? {
        switch self {
        case .noToken: "No GitHub token: run `gh auth login` or set a token in Settings"
        case .http(401): "GitHub rejected the token (HTTP 401): check the token in Settings or run `gh auth login`"
        case .http(403), .http(429): "GitHub's rate limit is reached for now (search allows 30 requests a minute). Try again in a minute."
        case let .http(code): "GitHub API returned HTTP \(code)"
        case let .api(message): message
        }
    }
}

/// One CI check: a GitHub Actions/Checks run or a commit status.
public struct RawCheck: Decodable, Sendable {
    public let name: String
    /// Check run status (QUEUED, IN_PROGRESS, COMPLETED…) or nil for a commit status.
    public let status: String?
    /// Check run conclusion, or the commit status state (SUCCESS, FAILURE, PENDING…).
    public let conclusion: String?
    public let url: String?
    public let startedAt: String?
    public let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name, status, conclusion, detailsUrl, startedAt, completedAt, checkSuite, context, state, targetUrl
    }

    private struct Suite: Decodable {
        struct Run: Decodable {
            struct Workflow: Decodable { let name: String }
            let workflow: Workflow
        }
        let workflowRun: Run?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if try c.decode(String.self, forKey: .typename) == "StatusContext" {
            name = try c.decode(String.self, forKey: .context)
            status = nil
            conclusion = try c.decodeIfPresent(String.self, forKey: .state)
            url = try c.decodeIfPresent(String.self, forKey: .targetUrl)
            startedAt = nil
            completedAt = nil
        } else {
            let job = try c.decode(String.self, forKey: .name)
            let workflow = (try? c.decodeIfPresent(Suite.self, forKey: .checkSuite))??.workflowRun?.workflow.name
            name = workflow.map { "\($0) / \(job)" } ?? job
            status = try c.decodeIfPresent(String.self, forKey: .status)
            conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion)
            url = try c.decodeIfPresent(String.self, forKey: .detailsUrl)
            startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt)
            completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        }
    }
}

extension Failable: Sendable where T: Sendable {}

/// Decodes a value, or nil when it cannot be read.
public struct Failable<T: Decodable>: Decodable {
    public let value: T?
    public init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private struct Response: Decodable {
    struct Search: Decodable { let nodes: [Failable<RawPullRequest>?] }
    struct Viewer: Decodable { let login: String }
    struct DataField: Decodable {
        let viewer: Viewer
        let mine: Search?
        let review: Search?
    }
    struct APIError: Decodable { let message: String }
    let data: DataField?
    let errors: [APIError]?
}

public enum GitHubClient {
    static let query = """
    query ($mine: String!, $review: String!) {
      viewer { login }
      mine: search(query: $mine, type: ISSUE, first: 50) { nodes { ...pr } }
      review: search(query: $review, type: ISSUE, first: 50) { nodes { ...pr } }
    }
    fragment pr on PullRequest {
      id number title url isDraft updatedAt mergeable mergeStateStatus reviewDecision additions deletions changedFiles
      recentCommits: commits(last: 5) { nodes { commit { oid messageHeadline committedDate author { name user { login } } } } }
      repository { nameWithOwner }
      author { login }
      comments(last: 10) { totalCount nodes { ...comment } }
      reviewThreads(last: 20) { totalCount nodes { path line isResolved comments(last: 5) { totalCount nodes { ...comment } } } }
      commits(last: 1) { totalCount nodes { commit { oid messageHeadline committedDate author { name user { login } } statusCheckRollup { state contexts(first: 50) { totalCount nodes {
        __typename
        ... on CheckRun { name status conclusion detailsUrl startedAt completedAt
          checkSuite { workflowRun { workflow { name } } } }
        ... on StatusContext { context state targetUrl }
      } } } } } }
      latestOpinionatedReviews(first: 50) { nodes { state submittedAt url author { login __typename avatarUrl(size: 48) } } }
      reviews(last: 30) { totalCount nodes { author { login __typename avatarUrl(size: 48) } } }
      reviewRequests(first: 10) { nodes { requestedReviewer {
        ... on User { login avatarUrl(size: 48) url } ... on Team { name url } ... on Bot { login } ... on Mannequin { login }
      } } }
      participants(first: 8) { totalCount nodes { login avatarUrl(size: 48) } }
    }
    fragment comment on Comment {
      author { login __typename avatarUrl(size: 48) } bodyText createdAt
      ... on IssueComment { url } ... on PullRequestReviewComment { url }
    }
    """

    public static func fetch(token: String, teamRequests: Bool) async throws -> SearchResult {
        let base = "is:open is:pr archived:false sort:updated-desc"
        let variables = [
            "mine": "\(base) author:@me",
            // team requests can include the viewer's own PRs (CODEOWNERS)
            "review": "\(base) -author:@me \(teamRequests ? "review-requested" : "user-review-requested"):@me",
        ]
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw GitHubError.http(http.statusCode) }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let body = decoded.data else { throw GitHubError.api(decoded.errors?.first?.message ?? "Empty GitHub response") }
        let nodes = { (search: Response.Search?) in (search?.nodes ?? []).compactMap { $0?.value } }
        var warnings: [String] = []
        for message in decoded.errors?.map(\.message) ?? [] where !warnings.contains(message) {
            warnings.append(message)
        }
        // a node that is present but does not decode is a PR this app cannot read
        let unreadable = [body.mine, body.review].reduce(0) { sum, search in
            sum + (search?.nodes ?? []).filter { $0 != nil && $0?.value == nil }.count
        }
        if unreadable > 0 { warnings.append("\(unreadable) pull request(s) could not be read") }
        return SearchResult(viewer: body.viewer.login, mine: nodes(body.mine), review: nodes(body.review), warnings: warnings)
    }
}
