import AppKit
import Foundation
import Observation
import os
import PRCore

private let log = Logger(subsystem: "PRStatus", category: "refresh")

private enum Key {
    static let layout = "layout.v1"
    static let settings = "settings.v1"
    static let seen = "seen.v1"
}

@MainActor
@Observable
final class Store {
    var snapshot: Snapshot?
    var error: String?
    var isLoading = false
    var lastRefresh: Date?
    var viewer: String?

    /// The contribution calendar, oldest day first; grows backwards as older years load.
    var calendar: [ContributionDay] = []
    var calendarLoadingOlder = false
    /// The activity row shows the whole calendar.
    var activityExpanded = false
    @ObservationIgnored private var calendarFrom: Date?
    @ObservationIgnored private var calendarTask: Task<Void, Never>?

    /// Insights per period, loaded when the Insights window asks for them.
    var insights: [InsightsPeriod: Insights] = [:]
    var insightsLoading: Set<InsightsPeriod> = []
    var insightsError: String?
    /// Shows hidden PRs in the dropdown until it is turned off again.
    var showHidden = false
    /// The highlighted row of the dropdown, moved by the arrow keys and the pointer: "pr:<id>" or "row:<name>".
    var selection: String?

    var layout: CardLayout { didSet { save(layout, Key.layout) } }
    var settings: AppSettings {
        didSet {
            save(settings, Key.settings)
            if oldValue.teamRequests != settings.teamRequests || oldValue.includeDrafts != settings.includeDrafts {
                Task { await refresh() }
            }
            if oldValue.refreshMinutes != settings.refreshMinutes { startTimer(refreshNow: false) }
            if oldValue.appearance != settings.appearance { applyAppearance() }
        }
    }

    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// The default layout with neutral icons for the made-up orgs: their GitHub avatars belong to real accounts.
    private static var demoLayout: CardLayout {
        var layout = CardLayout.default
        layout.aliases = [
            OrgAlias(org: "acme", iconKind: .symbol, iconValue: "building.2.fill"),
            OrgAlias(org: "globex", iconKind: .symbol, iconValue: "globe.americas.fill"),
        ]
        return layout
    }

    /// `--demo`: made-up PRs, activity and insights, default layout and settings, nothing saved. For screenshots.
    @ObservationIgnored let demo = CommandLine.arguments.contains("--demo")

    init() {
        let demo = CommandLine.arguments.contains("--demo")
        layout = demo ? Self.demoLayout : (Self.load(CardLayout.self, Key.layout) ?? .default).normalized()
        settings = demo ? AppSettings() : Self.load(AppSettings.self, Key.settings) ?? AppSettings()
    }

    private var hiddenIDs: Set<String> { Set(settings.hiddenPRs) }

    /// The snapshot without hidden PRs; the counts in the title use it.
    var shownSnapshot: Snapshot? { snapshot?.removing(hiddenIDs) }

    var sections: Sections? {
        (showHidden ? snapshot : shownSnapshot).map { visibleSections($0, settings) }
    }

    var hiddenCount: Int { snapshot?.all.filter { hiddenIDs.contains($0.id) }.count ?? 0 }

    func isHidden(_ pr: PullRequest) -> Bool { hiddenIDs.contains(pr.id) }

    func setHidden(_ pr: PullRequest, _ hidden: Bool) {
        settings.hiddenPRs.removeAll { $0 == pr.id }
        if hidden { settings.hiddenPRs.append(pr.id) }
        if hiddenCount == 0 { showHidden = false }
    }

    /// New PRs that count for the menu bar dot: shown, in a visible section, not dismissed.
    private var dotPRs: [PullRequest] {
        guard let snapshot = shownSnapshot else { return [] }
        let dismissed = Set(settings.dismissedPRs)
        return visibleSections(snapshot, settings).all.filter { $0.isNew && !dismissed.contains($0.id) }
    }

    var hasNew: Bool { !dotPRs.isEmpty }

    /// The most urgent state among the PRs behind the dot.
    var dotAttention: Attention? { dotPRs.map(\.attention).min() }

    /// The pointer entering a row selects it, as in a native menu; leaving clears it only if it still owns it.
    func hover(_ id: String, _ inside: Bool) {
        if inside { selection = id } else if selection == id { selection = nil }
    }

    func toggleSection(_ title: String) {
        if settings.collapsedSections.contains(title) {
            settings.collapsedSections.removeAll { $0 == title }
        } else {
            settings.collapsedSections.append(title)
        }
    }

    /// Opens the PR in the browser, marks it as seen and closes the dropdown.
    func open(_ pr: PullRequest) {
        if pr.isNew { markSeen([pr]) }
        MenuBarController.shared?.close()
        NSWorkspace.shared.open(pr.url)
    }

    func isDismissed(_ pr: PullRequest) -> Bool { settings.dismissedPRs.contains(pr.id) }

    func setDismissed(_ pr: PullRequest, _ dismissed: Bool) {
        settings.dismissedPRs.removeAll { $0 == pr.id }
        if dismissed { settings.dismissedPRs.append(pr.id) }
    }

    /// Explains the menu bar numbers on hover.
    var tooltip: String {
        guard let snapshot = shownSnapshot else { return error ?? "PR Status" }
        var lines = [
            "\(snapshot.review.count) waiting for your review",
            "\(snapshot.mine.count) of yours open, \(snapshot.ready.count) ready to merge",
        ]
        let byAttention = Dictionary(grouping: dotPRs, by: \.attention)
        for attention in byAttention.keys.sorted() {
            lines.append("\(settings.newSymbol) \(byAttention[attention]!.count) new: \(attention.label)")
        }
        if let error { lines.append("! \(error)") }
        return lines.joined(separator: "\n")
    }

    var title: String {
        guard let snapshot = shownSnapshot else { return error == nil ? "" : "!" }
        let text = formatTitle(settings.titleTemplate, snapshot: snapshot, newSymbol: settings.newSymbol, hasNew: hasNew)
        return error == nil ? text : "\(text) !"
    }

    func start() {
        applyAppearance()
        startTimer(refreshNow: true)
        startCalendarTimer()
    }

    /// The calendar changes slowly: the last year once, then the current days every 30 minutes.
    private func startCalendarTimer() {
        calendarTask?.cancel()
        calendarTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshCalendar()
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    func refreshCalendar() async {
        if demo {
            calendar = Samples.calendar()
            return
        }
        do {
            let token = try await Token.resolve()
            let to = Date.now
            let from = Calendar.current.date(byAdding: .day, value: -364, to: to)!
            let days = try await GitHubClient.fetchCalendar(token: token, from: from, to: to)
            // keep older years that were loaded by scrolling
            let older = calendar.filter { $0.date < (days.first?.date ?? from) }
            calendar = older + days
            if calendarFrom == nil { calendarFrom = days.first?.date ?? from }
        } catch {
            log.error("calendar refresh failed \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Loads the year before the oldest loaded day, for scrolling back in the calendar.
    func loadOlderCalendar() async {
        guard !calendarLoadingOlder, let oldest = calendar.first?.date else { return }
        calendarLoadingOlder = true
        defer { calendarLoadingOlder = false }
        do {
            let token = try await Token.resolve()
            let to = Calendar.current.date(byAdding: .second, value: -1, to: oldest)!
            let from = Calendar.current.date(byAdding: .day, value: -364, to: to)!
            let days = try await GitHubClient.fetchCalendar(token: token, from: from, to: to)
            calendar = days.filter { $0.date < oldest } + calendar
        } catch {
            log.error("older calendar failed \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadInsights(_ period: InsightsPeriod, force: Bool = false) async {
        if demo {
            insights[period] = Samples.insights(period)
            return
        }
        guard force || insights[period] == nil, !insightsLoading.contains(period) else { return }
        insightsLoading.insert(period)
        defer { insightsLoading.remove(period) }
        do {
            let token = try await Token.resolve()
            let login: String
            if let viewer { login = viewer } else { login = try await GitHubClient.fetchViewer(token: token) }
            let since = Calendar.current.date(byAdding: .day, value: -period.rawValue, to: .now)!
            async let commits = GitHubClient.fetchCommits(token: token, login: login, since: since)
            async let merged = GitHubClient.fetchMerged(token: token, since: since)
            let (c, m) = try await (commits, merged)
            insights[period] = Insights(period: period, commits: c.commits, commitsCapped: c.capped, merged: m)
            insightsError = nil
            log.info("insights loaded \(period.rawValue, privacy: .public) commits \(c.commits.count, privacy: .public) merged \(m.count, privacy: .public)")
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            insightsError = error.localizedDescription
            log.error("insights failed \(error.localizedDescription, privacy: .public)")
        }
    }

    /// nil follows macOS, including its automatic light/dark switch during the day.
    func applyAppearance() {
        NSApp.appearance = switch settings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// The timer only sleeps and triggers; a running fetch is never cancelled by a restart.
    private func startTimer(refreshNow: Bool) {
        timer?.cancel()
        let interval = UInt64(max(1, settings.refreshMinutes)) * 60 * 1_000_000_000
        timer = Task { [weak self] in
            var first = refreshNow
            while !Task.isCancelled {
                if !first { try? await Task.sleep(nanoseconds: interval) }
                first = false
                guard !Task.isCancelled, let self else { return }
                Task { await self.refresh() }
            }
        }
    }

    /// Refreshes when the data is older than a minute, e.g. when the popover opens after sleep.
    func refreshIfStale() {
        if let lastRefresh, Date.now.timeIntervalSince(lastRefresh) < 60 { return }
        Task { await refresh() }
    }

    func refresh() async {
        if demo {
            let prs = Samples.prs()
            snapshot = Snapshot(review: prs.filter { !$0.mine }, mine: prs.filter(\.mine), warnings: [])
            viewer = "me"
            lastRefresh = .now
            return
        }
        // a refresh asked for during a fetch (new settings, new token) runs once that fetch ends
        guard !isLoading else {
            refreshAgain = true
            return
        }
        isLoading = true
        defer {
            isLoading = false
            if refreshAgain {
                refreshAgain = false
                Task { await refresh() }
            }
        }
        do {
            let token = try await Token.resolve()
            let data = try await GitHubClient.fetch(token: token, teamRequests: settings.teamRequests)
            let stored = Self.load(SeenMap.self, Key.seen)
            let (snapshot, seen) = buildSnapshot(data, includeDrafts: settings.includeDrafts, stored: stored, now: .now)
            save(seen, Key.seen)
            self.snapshot = snapshot
            // forget hidden PRs that are closed or merged
            let open = Set(snapshot.all.map(\.id))
            if settings.hiddenPRs.contains(where: { !open.contains($0) }) {
                settings.hiddenPRs.removeAll { !open.contains($0) }
            }
            if settings.dismissedPRs.contains(where: { !open.contains($0) }) {
                settings.dismissedPRs.removeAll { !open.contains($0) }
            }
            error = nil
            lastRefresh = .now
            viewer = data.viewer
            if !data.warnings.isEmpty {
                log.warning("github partial errors \(data.warnings.count, privacy: .public)")
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            if case GitHubError.http(401) = error { Token.forgetCached() }
            self.error = error.localizedDescription
            log.error("refresh failed \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Stores the current activity of the PRs as seen and clears their new marker.
    func markSeen(_ prs: [PullRequest]) {
        var seen = Self.load(SeenMap.self, Key.seen) ?? [:]
        for pr in prs { seen[pr.id] = SeenEntry(activity: pr.activity, at: .now, seenAt: .now) }
        save(seen, Key.seen)
        let ids = Set(prs.map(\.id))
        guard var snapshot else { return }
        for i in snapshot.review.indices where ids.contains(snapshot.review[i].id) {
            snapshot.review[i].isNew = false
            snapshot.review[i].changes = []
            snapshot.review[i].markComments(newAfter: nil)
        }
        for i in snapshot.mine.indices where ids.contains(snapshot.mine[i].id) {
            snapshot.mine[i].isNew = false
            snapshot.mine[i].changes = []
            snapshot.mine[i].markComments(newAfter: nil)
        }
        self.snapshot = snapshot
    }

    private func save(_ value: some Encodable, _ key: String) {
        if demo { return }
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
