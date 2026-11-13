import AppKit
import PRCore
import SwiftUI

/// The dropdown, styled like a native macOS menu.
struct PopoverView: View {
    @Environment(Store.self) private var store
    @State private var contentHeight: CGFloat = 80
    @State private var totalHeight: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, 640))
            .scrollIndicators(contentHeight > 640 ? .automatic : .never)
            MenuSeparator()
            ActivityRow()
            MenuSeparator()
            actions
        }
        .padding(5)
        .frame(width: store.settings.popoverWidth)
        // natural height, not the window's: the window must be able to grow as well as shrink
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { totalHeight = $0 }
        .background(WindowSizer(height: totalHeight))
        .background(shortcuts)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: .down) { handle($0) }
        .onAppear {
            store.refreshIfStale()
            focused = true
        }
        .onDisappear { store.selection = nil }
    }

    private var visible: [(title: String, icon: String, prs: [PullRequest])] {
        guard let sections = store.sections else { return [] }
        let all = [
            (title: "Review Requested", icon: "eye", prs: sections.review),
            (title: "My Pull Requests", icon: "arrow.triangle.pull", prs: sections.mine),
            (title: "Ready to Merge", icon: "arrow.triangle.merge", prs: sections.ready),
        ]
        return all.filter { !$0.prs.isEmpty }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let error = store.error {
                Notice(icon: "exclamationmark.triangle.fill", color: .orange, text: error)
            }
            ForEach(store.snapshot?.warnings ?? [], id: \.self) { warning in
                Notice(icon: "exclamationmark.circle", color: .yellow, text: warning)
            }
            if store.sections != nil {
                ForEach(Array(visible.enumerated()), id: \.offset) { index, section in
                    if index > 0 { MenuSeparator() }
                    SectionView(title: section.title, icon: section.icon, prs: section.prs)
                }
                if visible.isEmpty {
                    MenuHeader(text: "No open pull requests")
                }
            } else if store.error == nil {
                MenuHeader(text: "Loading…")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        let newPRs = store.sections?.all.filter(\.isNew) ?? []
        if !newPRs.isEmpty {
            MenuRow(id: "seen", icon: "checkmark.circle", title: "Mark All as Seen (\(newPRs.count))") { store.markSeen(newPRs) }
        }
        if store.hiddenCount > 0 {
            MenuRow(id: "hidden", icon: store.showHidden ? "eye.slash" : "eye",
                    title: store.showHidden ? "Hide Hidden PRs" : "Show Hidden PRs (\(store.hiddenCount))") {
                store.showHidden.toggle()
            }
        }
        GroupByRow()
        MenuRow(id: "refresh", icon: "arrow.clockwise", title: "Refresh", detail: updatedText, shortcut: "⌘R") {
            Task { await store.refresh() }
        }
        MenuRow(id: "insights", icon: "chart.bar.xaxis", title: "Insights…", shortcut: "⌘I", action: showInsights)
        MenuRow(id: "github", icon: "arrow.up.right.square", title: "Open Pull Requests on GitHub", action: openGitHub)
        MenuSeparator()
        MenuRow(id: "settings", icon: "gearshape", title: "Settings…", shortcut: "⌘,", action: showSettings)
        MenuRow(id: "quit", icon: "power", title: "Quit GitHub Radar", shortcut: "⌘Q") { NSApp.terminate(nil) }
    }

    private var updatedText: String? {
        if store.isLoading { return "Updating…" }
        guard let last = store.lastRefresh else { return nil }
        return last.timeIntervalSinceNow > -60 ? "just now" : "\(relativeAge(last, now: .now)) ago"
    }

    private func showSettings() {
        closeDropdown()
        SettingsWindow.shared.show(store)
    }

    private func showInsights() {
        InsightsWindow.shared.show(store)
    }

    private func openGitHub() {
        closeDropdown()
        NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!)
    }

    // MARK: keyboard

    /// Everything the arrow keys walk through, in screen order, with what ↩ does on it.
    private var navigation: [(id: String, pr: PullRequest?, section: String?, run: () -> Void)] {
        var items: [(id: String, pr: PullRequest?, section: String?, run: () -> Void)] = []
        for section in visible {
            let title = section.title
            if store.settings.collapsedSections.contains(title) {
                items.append(("section:\(title)", nil, title, { store.toggleSection(title) }))
                continue
            }
            for pr in orderedForDisplay(section.prs, by: store.settings.groupBy) {
                items.append(("pr:\(pr.id)", pr, title, { store.open(pr) }))
            }
        }
        items.append(("row:activity", nil, nil, { store.activityExpanded.toggle() }))
        let newPRs = store.sections?.all.filter(\.isNew) ?? []
        if !newPRs.isEmpty { items.append(("row:seen", nil, nil, { store.markSeen(newPRs) })) }
        if store.hiddenCount > 0 { items.append(("row:hidden", nil, nil, { store.showHidden.toggle() })) }
        items.append(("row:group", nil, nil, { store.settings.groupBy = store.settings.groupBy.next }))
        items.append(("row:refresh", nil, nil, { Task { await store.refresh() } }))
        items.append(("row:insights", nil, nil, showInsights))
        items.append(("row:github", nil, nil, openGitHub))
        items.append(("row:settings", nil, nil, showSettings))
        items.append(("row:quit", nil, nil, { NSApp.terminate(nil) }))
        return items
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let items = navigation
        let index = items.firstIndex { $0.id == store.selection }
        let current = index.map { items[$0] }
        switch press.key {
        case .downArrow:
            store.selection = items[index.map { min($0 + 1, items.count - 1) } ?? 0].id
        case .upArrow:
            store.selection = items[index.map { max($0 - 1, 0) } ?? items.count - 1].id
        case .return, .space:
            current?.run()
        case .leftArrow, .rightArrow:
            guard let section = current?.section else { return .ignored }
            let collapsed = store.settings.collapsedSections.contains(section)
            if (press.key == .leftArrow) != collapsed {
                store.toggleSection(section)
                // ← lands on the collapsed header, → on the first PR of the opened section
                store.selection = press.key == .leftArrow
                    ? "section:\(section)"
                    : navigation.first { $0.section == section && $0.pr != nil }.map(\.id) ?? store.selection
            }
        default:
            guard let pr = current?.pr else { return .ignored }
            switch press.characters.lowercased() {
            case "h": store.setHidden(pr, !store.isHidden(pr))
            case "m", "d": store.setDismissed(pr, !store.isDismissed(pr))
            case "c":
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            default: return .ignored
            }
        }
        return .handled
    }

    /// Invisible buttons, so the shortcuts shown in the rows work while the dropdown is open.
    private var shortcuts: some View {
        ZStack {
            Button("") { Task { await store.refresh() } }.keyboardShortcut("r")
            Button("", action: showSettings).keyboardShortcut(",")
            Button("", action: showInsights).keyboardShortcut("i")
            Button("") { store.settings.groupBy = store.settings.groupBy.next }.keyboardShortcut("g")
            Button("") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .opacity(0)
        .allowsHitTesting(false)
    }
}

/// PRs by org or repo, groups in name order, PRs keep their order inside a group.
func groupPRs(_ prs: [PullRequest], by groupBy: GroupBy) -> [(key: String, prs: [PullRequest])] {
    guard groupBy != .none else { return [("", prs)] }
    let key: (PullRequest) -> String = groupBy == .org ? { $0.org } : { $0.repo }
    var order: [String] = []
    var byKey: [String: [PullRequest]] = [:]
    for pr in prs {
        let k = key(pr)
        if byKey[k] == nil { order.append(k) }
        byKey[k, default: []].append(pr)
    }
    return order.sorted { $0.lowercased() < $1.lowercased() }.map { ($0, byKey[$0]!) }
}

/// The PRs of a section in the order the dropdown shows them.
func orderedForDisplay(_ prs: [PullRequest], by groupBy: GroupBy) -> [PullRequest] {
    groupPRs(prs, by: groupBy).flatMap(\.prs)
}

/// Closes the dropdown, as a native menu closes after a pick.
@MainActor
func closeDropdown() {
    MenuBarController.shared?.close()
}

/// "Group by" as a menu row; a click opens a native menu with None / Org / Repo. ⌘G cycles it too.
private struct GroupByRow: View {
    @Environment(Store.self) private var store
    @State private var showMenu = false

    private var hovered: Bool { store.selection == "row:group" }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "square.stack.3d.up").frame(width: 16)
            Text("Group by")
            Spacer(minLength: 12)
            Text(store.settings.groupBy.label).opacity(0.6)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.6)
            Text("⌘G").opacity(0.5)
        }
        .font(.system(size: 13))
        .foregroundStyle(hovered ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { store.hover("row:group", $0) }
        .pointingHand()
        .background(MenuAnchor(show: showMenu))
        .onTapGesture { showMenu.toggle() }
    }
}

/// Pops up a native menu with the group-by choices, under the row that owns it.
private struct MenuAnchor: NSViewRepresentable {
    @Environment(Store.self) private var store
    var show: Bool

    func makeNSView(context _: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        guard show != context.coordinator.shown else { return }
        context.coordinator.shown = show
        let menu = NSMenu()
        for choice in GroupBy.allCases {
            let item = NSMenuItem(title: choice.label, action: #selector(Coordinator.pick(_:)), keyEquivalent: "")
            item.target = context.coordinator
            item.representedObject = choice.rawValue
            item.state = store.settings.groupBy == choice ? .on : .off
            menu.addItem(item)
        }
        context.coordinator.store = store
        DispatchQueue.main.async {
            menu.popUp(positioning: menu.items.first { $0.state == .on }, at: NSPoint(x: view.bounds.maxX - 110, y: view.bounds.maxY), in: view)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var shown = false
        var store: Store?

        @objc func pick(_ item: NSMenuItem) {
            guard let raw = item.representedObject as? String, let choice = GroupBy(rawValue: raw) else { return }
            store?.settings.groupBy = choice
        }
    }
}

/// Resizes the hosting window to the content height and keeps its top edge in place.
/// Keeps the dropdown panel as tall as its content, e.g. after a section collapses.
private struct WindowSizer: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context _: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context _: Context) {
        let height = height
        DispatchQueue.main.async {
            guard height > 0, let window = view.window else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - height) > 0.5 else { return }
            var frame = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.minY, width: content.width, height: height))
            frame.origin.y = window.frame.maxY - frame.height
            window.setFrame(frame, display: true)
        }
    }
}

// MARK: - Native menu pieces

struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
    }
}

private struct MenuHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.65))
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 3)
    }
}

/// A plain menu item: icon, title, optional detail and shortcut, accent highlight on hover.
private struct MenuRow: View {
    @Environment(Store.self) private var store
    let id: String
    let icon: String
    let title: String
    var detail: String?
    var shortcut: String?
    let action: () -> Void

    private var hovered: Bool { store.selection == "row:\(id)" }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon).frame(width: 16)
            Text(title)
            Spacer(minLength: 12)
            if let detail { Text(detail).opacity(0.6) }
            if let shortcut { Text(shortcut).opacity(0.5) }
        }
        .font(.system(size: 13))
        .foregroundStyle(hovered ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { store.hover("row:\(id)", $0) }
        .pointingHand()
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, action)
    }
}

private struct Notice: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
    }
}

private struct SectionView: View {
    @Environment(Store.self) private var store
    @State private var hovered = false
    let title: String
    let icon: String
    let prs: [PullRequest]

    private var collapsed: Bool { store.settings.collapsedSections.contains(title) }
    private var selected: Bool { store.selection == "section:\(title)" }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).frame(width: 16)
            Text("\(title) (\(prs.count))")
            if collapsed, prs.contains(where: \.isNew) {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(collapsed ? 0 : 90))
                .opacity(hovered || collapsed ? 1 : 0.4)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.primary.opacity(hovered ? 0.85 : 0.65))
        .padding(.horizontal, 9)
        .padding(.top, 4)
        .padding(.bottom, 3)
        .contentShape(Rectangle())
        .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.primary.opacity(0.1) : .clear))
        .onHover { hovered = $0 }
        .pointingHand()
        .onTapGesture { store.toggleSection(title) }
        .help(collapsed ? "Expand (→)" : "Collapse (←)")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint(collapsed ? "Expand" : "Collapse")
        .accessibilityAction(.default) { store.toggleSection(title) }
        if !collapsed {
            if store.settings.groupBy == .none {
                cards(prs)
            } else {
                ForEach(groupPRs(prs, by: store.settings.groupBy), id: \.key) { group in
                    GroupHeader(sample: group.prs[0], groupBy: store.settings.groupBy, count: group.prs.count)
                    cards(group.prs)
                }
            }
        }
    }

    private func cards(_ prs: [PullRequest]) -> some View {
        ForEach(Array(prs.enumerated()), id: \.element.id) { index, pr in
            if index > 0 { MenuSeparator() }
            CardRow(pr: pr)
        }
    }
}

/// The title of an org or repo group inside a section: its icon, its name (or alias) and how many PRs.
private struct GroupHeader: View {
    @Environment(Store.self) private var store
    let sample: PullRequest
    let groupBy: GroupBy
    let count: Int

    var body: some View {
        let alias = store.layout.alias(for: sample.org)
        let org = alias.map { $0.hideOrg ? "" : ($0.alias.isEmpty ? sample.org : $0.alias) } ?? sample.org
        let name = groupBy == .org ? (org.isEmpty ? sample.org : org) : (org.isEmpty ? sample.repoName : "\(org)/\(sample.repoName)")
        HStack(spacing: 5) {
            Avatar(login: sample.org, url: URL(string: "https://github.com/\(sample.org).png?size=40"), size: 14)
            Text(name).font(.system(size: 12, weight: .semibold))
            Text("\(count)").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.5))
            Spacer()
        }
        .foregroundStyle(Color.primary.opacity(0.7))
        .linked(URL(string: "https://github.com/\(groupBy == .org ? sample.org : sample.repo)"))
        .padding(.horizontal, 9)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

private struct CardRow: View {
    @Environment(Store.self) private var store
    let pr: PullRequest

    private var hovered: Bool { store.selection == "pr:\(pr.id)" }

    var body: some View {
        let hidden = store.isHidden(pr)
        CardView(pr: pr, layout: store.layout, settings: store.settings, highlighted: hovered,
                 hideFirstLineTrailing: hovered)
            .opacity(hidden && !hovered ? 0.45 : 1)
            .overlay(alignment: .topTrailing) {
                let dismissed = store.isDismissed(pr)
                HStack(spacing: 2) {
                    if hovered || dismissed {
                        CardAction(icon: dismissed ? "bell.slash" : "bell", hovered: hovered,
                                   help: dismissed ? "Let this PR change the menu bar dot again"
                                       : "Dismiss: keep this PR in the list, but it no longer changes the menu bar dot") {
                            store.setDismissed(pr, !dismissed)
                        }
                    }
                    if hovered || hidden {
                        CardAction(icon: hidden ? "eye.slash" : "eye", hovered: hovered,
                                   help: hidden ? "Show this PR again" : "Hide this PR from the list and the counts") {
                            store.setHidden(pr, !hidden)
                        }
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? Color.accentColor : .clear))
            .contentShape(Rectangle())
            .onHover { store.hover("pr:\(pr.id)", $0) }
            .pointingHand()
            .onTapGesture { store.open(pr) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("Return opens it. H hides, M dismisses, C copies the link.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default) { store.open(pr) }
            .accessibilityAction(named: store.isHidden(pr) ? "Show" : "Hide") { store.setHidden(pr, !store.isHidden(pr)) }
            .accessibilityAction(named: store.isDismissed(pr) ? "Undismiss" : "Dismiss") {
                store.setDismissed(pr, !store.isDismissed(pr))
            }
    }

    /// What VoiceOver reads for the card.
    private var accessibilityText: String {
        var parts = ["\(pr.repo) pull request \(pr.number)", pr.title, pr.ci.label, pr.reviewLabel]
        if pr.isDraft { parts.insert("Draft", at: 1) }
        if pr.comments > 0 { parts.append("\(pr.comments) comments") }
        if pr.isNew { parts.insert("New activity", at: 0) }
        return parts.joined(separator: ", ")
    }
}

private struct CardAction: View {
    let icon: String
    let hovered: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundStyle(hovered ? Color.white : Color.primary.opacity(0.6))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .pointingHand()
    }
}
