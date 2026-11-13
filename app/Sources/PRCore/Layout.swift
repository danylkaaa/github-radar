import Foundation

public enum ElementID: String, Codable, CaseIterable, Sendable {
    case new, repo, commit, title, updated, ci, reviews, comments, size, author, draft, participants

    public var label: String {
        switch self {
        case .new: "New marker"
        case .repo: "Repo #"
        case .commit: "Commit"
        case .size: "+/− lines"
        case .title: "Title"
        case .updated: "Updated"
        case .ci: "CI"
        case .reviews: "Reviews"
        case .comments: "Comments"
        case .author: "Author"
        case .draft: "Draft"
        case .participants: "Participants"
        }
    }

    public var symbol: String {
        switch self {
        case .new: "circle.fill"
        case .repo: "folder"
        case .commit: "circle.and.line.horizontal"
        case .size: "plusminus"
        case .title: "textformat"
        case .updated: "clock"
        case .ci: "checkmark.circle"
        case .reviews: "person.2"
        case .comments: "bubble.left"
        case .author: "person"
        case .draft: "pencil.circle"
        case .participants: "person.2.circle"
        }
    }
}

public enum ElementStyle: String, Codable, CaseIterable, Sendable {
    case iconAndText, icon, text

    public var label: String {
        switch self {
        case .iconAndText: "Icon and text"
        case .icon: "Icon only"
        case .text: "Text only"
        }
    }
}

public struct LayoutElement: Codable, Hashable, Identifiable, Sendable {
    public var id: ElementID
    public var visible: Bool
    /// 1-based line of the card.
    public var line: Int
    public var style: ElementStyle

    public init(_ id: ElementID, line: Int, visible: Bool = true, style: ElementStyle = .iconAndText) {
        self.id = id
        self.visible = visible
        self.line = line
        self.style = style
    }
}

public enum OrgIconKind: String, Codable, CaseIterable, Sendable {
    case none, avatar, symbol, emoji

    public var label: String {
        switch self {
        case .none: "None"
        case .avatar: "GitHub avatar"
        case .symbol: "SF Symbol"
        case .emoji: "Emoji or text"
        }
    }
}

public struct OrgAlias: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var org: String
    /// Text shown instead of the org name; empty keeps the org name.
    public var alias: String
    /// Show only the repo name, without the org or its alias.
    public var hideOrg: Bool
    public var iconKind: OrgIconKind
    /// SF Symbol name or emoji, by `iconKind`.
    public var iconValue: String

    public init(org: String, alias: String = "", iconKind: OrgIconKind = .avatar, iconValue: String = "") {
        id = UUID()
        hideOrg = false
        self.org = org
        self.alias = alias
        self.iconKind = iconKind
        self.iconValue = iconValue
    }
}

public struct CardLayout: Codable, Equatable, Sendable {
    public var elements: [LayoutElement]
    public var aliases: [OrgAlias]

    public init(elements: [LayoutElement], aliases: [OrgAlias]) {
        self.elements = elements
        self.aliases = aliases
    }

    /// Skips elements and aliases it cannot read, so one bad entry does not reset the whole layout.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elements = (try? c.decode([Failable<LayoutElement>].self, forKey: .elements))?.compactMap(\.value) ?? []
        aliases = (try? c.decode([Failable<OrgAlias>].self, forKey: .aliases))?.compactMap(\.value) ?? []
    }

    public static let `default` = CardLayout(
        elements: [
            LayoutElement(.new, line: 1, style: .icon),
            LayoutElement(.repo, line: 1),
            LayoutElement(.draft, line: 1, style: .text),
            LayoutElement(.size, line: 1, style: .text),
            LayoutElement(.updated, line: 1, style: .text),
            LayoutElement(.title, line: 2),
            LayoutElement(.commit, line: 3),
            LayoutElement(.ci, line: 4),
            LayoutElement(.reviews, line: 4),
            LayoutElement(.comments, line: 4),
            LayoutElement(.author, line: 4),
            LayoutElement(.participants, line: 4),
        ],
        aliases: []
    )

    /// Visible elements grouped by line, in order.
    public var lines: [[LayoutElement]] {
        let visible = elements.filter(\.visible)
        return Set(visible.map(\.line)).sorted().map { line in visible.filter { $0.line == line } }
    }

    public var hidden: [LayoutElement] { elements.filter { !$0.visible } }

    public func element(_ id: ElementID) -> LayoutElement? { elements.first { $0.id == id } }

    /// Puts an element on `line` before `before` (or at the end of the line) and shows it.
    /// Line 0 makes a new first line; a line after the last makes a new last line.
    public mutating func place(_ id: ElementID, line: Int, before: ElementID? = nil) {
        guard id != before, var moved = element(id) else { return }
        elements.removeAll { $0.id == id }
        moved.visible = true
        moved.line = line
        if let before, let index = elements.firstIndex(where: { $0.id == before }) {
            elements.insert(moved, at: index)
        } else if let last = elements.lastIndex(where: { $0.visible && $0.line == line }) {
            elements.insert(moved, at: last + 1)
        } else {
            elements.append(moved)
        }
        compact()
    }

    public mutating func hide(_ id: ElementID) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].visible = false
        compact()
    }

    public mutating func setStyle(_ id: ElementID, _ style: ElementStyle) {
        guard let index = elements.firstIndex(where: { $0.id == id }) else { return }
        elements[index].style = style
    }

    /// Renumbers the lines of visible elements to 1...n and keeps them sorted by line.
    mutating func compact() {
        let lines = Set(elements.filter(\.visible).map(\.line)).sorted()
        for i in elements.indices where elements[i].visible {
            elements[i].line = (lines.firstIndex(of: elements[i].line) ?? 0) + 1
        }
        let order = Dictionary(uniqueKeysWithValues: elements.enumerated().map { ($1.id, $0) })
        elements.sort { a, b in
            let la = a.visible ? a.line : Int.max, lb = b.visible ? b.line : Int.max
            return la != lb ? la < lb : order[a.id]! < order[b.id]!
        }
    }

    /// Adds elements a stored layout of an older version does not have, on its last line.
    /// A stored layout lists every element, hidden ones too, so a missing one is new, not hidden by the user.
    public func normalized() -> CardLayout {
        var copy = self
        var seen = Set<ElementID>()
        copy.elements = copy.elements.filter { seen.insert($0.id).inserted }
        let lastLine = copy.elements.filter(\.visible).map(\.line).max() ?? 1
        for id in ElementID.allCases where !seen.contains(id) {
            // the commit hash belongs next to the PR number
            if id == .commit, let repo = copy.elements.firstIndex(where: { $0.id == .repo }) {
                copy.elements.insert(LayoutElement(id, line: copy.elements[repo].line,
                                                   visible: copy.elements[repo].visible, style: .text), at: repo + 1)
            } else {
                // a new element takes its style from the default layout
                let style = CardLayout.default.element(id)?.style ?? .iconAndText
                copy.elements.append(LayoutElement(id, line: lastLine, style: style))
            }
        }
        copy.compact()
        return copy
    }

    public func alias(for org: String) -> OrgAlias? {
        aliases.first { normalizeOrg($0.org).caseInsensitiveCompare(org) == .orderedSame }
    }

    public func repoLabel(_ pr: PullRequest) -> String {
        guard let alias = alias(for: pr.org) else { return "\(pr.repo)#\(pr.number)" }
        if alias.hideOrg { return "\(pr.repoName)#\(pr.number)" }
        let org = alias.alias.isEmpty ? pr.org : alias.alias
        return "\(org)/\(pr.repoName)#\(pr.number)"
    }
}

extension OrgAlias {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        org = try c.decode(String.self, forKey: .org)
        alias = try c.decodeIfPresent(String.self, forKey: .alias) ?? ""
        hideOrg = try c.decodeIfPresent(Bool.self, forKey: .hideOrg) ?? false
        iconKind = (try? c.decode(OrgIconKind.self, forKey: .iconKind)) ?? .avatar
        iconValue = try c.decodeIfPresent(String.self, forKey: .iconValue) ?? ""
    }
}

/// Cleans an org typed by the user: "@acme" and "acme/api" become "acme".
public func normalizeOrg(_ text: String) -> String {
    var org = text.trimmingCharacters(in: .whitespaces)
    if org.hasPrefix("@") { org.removeFirst() }
    return String(org.split(separator: "/").first ?? "")
}

public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case numbers, icons, status, text

    public var label: String {
        switch self {
        case .numbers: "Numbers"
        case .icons: "Icons"
        case .status: "Status icon"
        case .text: "Text template"
        }
    }
}

public enum CommitStyle: String, Codable, CaseIterable, Sendable {
    /// `8e142eb`
    case hash
    /// `8e142eb Read bucket size from config`
    case hashAndMessage
    /// `8e142eb Read bucket size from config · jdoe · 5m ago`, meant for a line of its own
    case full
    /// the hash in a small pill; the message shows on hover
    case pill

    public var label: String {
        switch self {
        case .hash: "Hash"
        case .hashAndMessage: "Hash and message"
        case .full: "Hash, message, author, time"
        case .pill: "Hash pill"
        }
    }
}

public enum GroupBy: String, Codable, CaseIterable, Sendable {
    case none, org, repo

    public var label: String {
        switch self {
        case .none: "None"
        case .org: "Org"
        case .repo: "Repo"
        }
    }

    public var next: GroupBy {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self {
        case .system: "Same as macOS"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var titleTemplate = "{review} / {mine}  ✓{ready} {new}"
    public var newSymbol = "•"
    public var separator = ""
    public var titleMaxLines = 2
    public var popoverWidth = 420.0
    public var refreshMinutes = 2
    public var showReview = true
    public var showMine = true
    public var showReady = true
    public var includeDrafts = true
    public var teamRequests = true
    public var previewRealData = false
    public var collapsedSections: [String] = []
    /// Ids of PRs the user hid from the dropdown and the counts.
    public var hiddenPRs: [String] = []
    /// Ids of PRs the user dismissed: they stay in the list but do not change the menu bar dot.
    public var dismissedPRs: [String] = []
    public var menuBarStyle: MenuBarStyle = .numbers
    public var showReviewCount = true
    public var showMineCount = true
    public var showReadyCount = true
    public var hideZeroCounts = false
    public var appearance: AppAppearance = .system
    public var commitStyle: CommitStyle = .full
    public var groupBy: GroupBy = .none
    /// ⌥⌘P opens the dropdown from any app.
    public var globalShortcut = true

    public init() {}

    public init(from decoder: Decoder) throws {
        // missing keys keep their defaults, so older stored settings still decode
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        titleTemplate = try c.decodeIfPresent(String.self, forKey: .titleTemplate) ?? d.titleTemplate
        newSymbol = try c.decodeIfPresent(String.self, forKey: .newSymbol) ?? d.newSymbol
        separator = try c.decodeIfPresent(String.self, forKey: .separator) ?? d.separator
        titleMaxLines = try c.decodeIfPresent(Int.self, forKey: .titleMaxLines) ?? d.titleMaxLines
        popoverWidth = try c.decodeIfPresent(Double.self, forKey: .popoverWidth) ?? d.popoverWidth
        refreshMinutes = try c.decodeIfPresent(Int.self, forKey: .refreshMinutes) ?? d.refreshMinutes
        showReview = try c.decodeIfPresent(Bool.self, forKey: .showReview) ?? d.showReview
        showMine = try c.decodeIfPresent(Bool.self, forKey: .showMine) ?? d.showMine
        showReady = try c.decodeIfPresent(Bool.self, forKey: .showReady) ?? d.showReady
        includeDrafts = try c.decodeIfPresent(Bool.self, forKey: .includeDrafts) ?? d.includeDrafts
        teamRequests = try c.decodeIfPresent(Bool.self, forKey: .teamRequests) ?? d.teamRequests
        previewRealData = try c.decodeIfPresent(Bool.self, forKey: .previewRealData) ?? d.previewRealData
        collapsedSections = try c.decodeIfPresent([String].self, forKey: .collapsedSections) ?? d.collapsedSections
        hiddenPRs = try c.decodeIfPresent([String].self, forKey: .hiddenPRs) ?? d.hiddenPRs
        dismissedPRs = try c.decodeIfPresent([String].self, forKey: .dismissedPRs) ?? d.dismissedPRs
        menuBarStyle = (try? c.decodeIfPresent(MenuBarStyle.self, forKey: .menuBarStyle)) ?? d.menuBarStyle
        showReviewCount = try c.decodeIfPresent(Bool.self, forKey: .showReviewCount) ?? d.showReviewCount
        showMineCount = try c.decodeIfPresent(Bool.self, forKey: .showMineCount) ?? d.showMineCount
        showReadyCount = try c.decodeIfPresent(Bool.self, forKey: .showReadyCount) ?? d.showReadyCount
        hideZeroCounts = try c.decodeIfPresent(Bool.self, forKey: .hideZeroCounts) ?? d.hideZeroCounts
        appearance = (try? c.decodeIfPresent(AppAppearance.self, forKey: .appearance)) ?? d.appearance
        commitStyle = (try? c.decodeIfPresent(CommitStyle.self, forKey: .commitStyle)) ?? d.commitStyle
        groupBy = (try? c.decodeIfPresent(GroupBy.self, forKey: .groupBy)) ?? d.groupBy
        globalShortcut = try c.decodeIfPresent(Bool.self, forKey: .globalShortcut) ?? d.globalShortcut
    }
}

public struct Sections: Sendable {
    public var review: [PullRequest]
    public var mine: [PullRequest]
    public var ready: [PullRequest]

    public var all: [PullRequest] { review + mine + ready }
}

extension Snapshot {
    /// The snapshot without the PRs whose ids are in `hidden`.
    public func removing(_ hidden: Set<String>) -> Snapshot {
        Snapshot(
            review: review.filter { !hidden.contains($0.id) },
            mine: mine.filter { !hidden.contains($0.id) },
            warnings: warnings
        )
    }
}

/// PRs per popover section, each with new activity first, then the most recently updated.
/// A ready PR shows under "My pull requests" only when the ready section is off.
public func visibleSections(_ snapshot: Snapshot, _ settings: AppSettings) -> Sections {
    Sections(
        review: settings.showReview ? sortedForList(snapshot.review) : [],
        mine: settings.showMine ? sortedForList(snapshot.mine.filter { !settings.showReady || !$0.ready }) : [],
        ready: settings.showReady ? sortedForList(snapshot.ready) : []
    )
}

/// New activity first, then the most recently updated.
public func sortedForList(_ prs: [PullRequest]) -> [PullRequest] {
    prs.sorted { a, b in a.isNew != b.isNew ? a.isNew : a.updatedAt > b.updatedAt }
}
