import PRCore
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            LayoutEditor().tabItem { Label("Card Layout", systemImage: "rectangle.3.group") }
            OrgsEditor().tabItem { Label("Orgs", systemImage: "building.2") }
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
        }
        .frame(width: 780, height: 620)
    }
}

// MARK: - Layout

private struct LayoutEditor: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Drag chips to reorder them, move them to another line or onto a new line. Drag a chip to Hidden to remove it. Right-click a chip for its style.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                NewLineZone(line: 0)
                ForEach(Array(store.layout.lines.enumerated()), id: \.offset) { index, line in
                    LineRow(number: index + 1, elements: line)
                }
                NewLineZone(line: store.layout.lines.count + 1)
                HiddenPalette()
                Spacer()
                Button("Reset to Default") { store.layout.elements = CardLayout.default.elements }
            }
            .frame(width: 380)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Preview").font(.headline)
                    Spacer()
                    Toggle("My PRs", isOn: $store.settings.previewRealData)
                        .toggleStyle(.switch).controlSize(.small)
                        .disabled(store.snapshot == nil)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        let prs = previewPRs
                        ForEach(Array(prs.enumerated()), id: \.element.id) { index, pr in
                            if index > 0 { Divider() }
                            CardView(pr: pr, layout: store.layout, settings: store.settings)
                                .padding(.horizontal, 10).padding(.vertical, 8)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.separator))
            }
        }
        .padding(20)
    }

    private var previewPRs: [PullRequest] {
        if store.settings.previewRealData, let all = store.snapshot?.all, !all.isEmpty { return Array(all.prefix(4)) }
        return Samples.prs()
    }
}

private struct LineRow: View {
    @Environment(Store.self) private var store
    @State private var targeted = false
    let number: Int
    let elements: [LayoutElement]

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("Line \(number)").font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                .padding(.top, 6)
            FlowLayout(spacing: 6) {
                ForEach(elements) { element in
                    Chip(element: element, line: number)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 8).fill(targeted ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08)))
        .dropDestination(for: String.self) { items, _ in
            drop(items) { store.layout.place($0, line: number) }
        } isTargeted: { targeted = $0 }
    }
}

private struct NewLineZone: View {
    @Environment(Store.self) private var store
    @State private var targeted = false
    let line: Int

    var body: some View {
        Text(line == 0 ? "Drop here for a new first line" : "Drop here for a new line")
            .font(.caption)
            .foregroundStyle(targeted ? Color.accentColor : .secondary)
            .frame(maxWidth: .infinity, minHeight: targeted ? 36 : 22)
            .background(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4)))
            .dropDestination(for: String.self) { items, _ in
                drop(items) { store.layout.place($0, line: line) }
            } isTargeted: { targeted = $0 }
            .animation(.easeOut(duration: 0.12), value: targeted)
    }
}

private struct HiddenPalette: View {
    @Environment(Store.self) private var store
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hidden").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if store.layout.hidden.isEmpty {
                    Text("Drag a chip here to hide it").font(.caption).foregroundStyle(.tertiary)
                }
                FlowLayout(spacing: 6) {
                    ForEach(store.layout.hidden) { element in
                        Chip(element: element, line: nil)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(targeted ? Color.red.opacity(0.12) : Color.secondary.opacity(0.05)))
            .dropDestination(for: String.self) { items, _ in
                drop(items) { store.layout.hide($0) }
            } isTargeted: { targeted = $0 }
        }
    }
}

private struct Chip: View {
    @Environment(Store.self) private var store
    @State private var targeted = false
    @State private var width: CGFloat = 0
    let element: LayoutElement
    /// nil for a chip in the hidden palette.
    let line: Int?

    var body: some View {
        HStack(spacing: 4) {
            if element.style != .text { Image(systemName: element.id.symbol).font(.caption) }
            Text(element.id.label).font(.callout)
                .foregroundStyle(element.style == .icon ? .secondary : .primary)
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(line == nil ? Color.secondary.opacity(0.15) : Color.accentColor.opacity(0.18)))
        .overlay(alignment: .leading) {
            if targeted { Capsule().fill(Color.accentColor).frame(width: 3).offset(x: -5) }
        }
        .draggable(element.id.rawValue) {
            Text(element.id.label).padding(6).background(Capsule().fill(Color.accentColor.opacity(0.3)))
        }
        .dropDestination(for: String.self) { items, location in
            guard let line else { return drop(items) { store.layout.hide($0) } }
            // the right half of a chip means "after it"
            let before = location.x < width / 2 ? element.id : nextOnLine(line)
            return drop(items) { id in
                if id == before { return }
                store.layout.place(id, line: line, before: before)
            }
        } isTargeted: { targeted = $0 && line != nil }
        .contextMenu {
            Picker("Style", selection: Binding(
                get: { element.style },
                set: { store.layout.setStyle(element.id, $0) }
            )) {
                ForEach(ElementStyle.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            if line != nil {
                Button("Hide") { store.layout.hide(element.id) }
            } else {
                Button("Add to last line") { store.layout.place(element.id, line: store.layout.lines.count) }
            }
        }
        .help(line == nil ? "Drag onto a line to show it" : "\(element.style.label). Right-click to change.")
    }

    private func nextOnLine(_ line: Int) -> ElementID? {
        let ids = store.layout.lines[safe: line - 1]?.map(\.id) ?? []
        guard let index = ids.firstIndex(of: element.id), index + 1 < ids.count else { return nil }
        return ids[index + 1]
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Applies a drop of element ids; false when none is known.
private func drop(_ items: [String], _ apply: (ElementID) -> Void) -> Bool {
    let ids = items.compactMap(ElementID.init(rawValue:))
    ids.forEach(apply)
    return !ids.isEmpty
}

// MARK: - Orgs

private struct OrgsEditor: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 12) {
            Text("Show a short name or an emoji instead of the org name, and pick an icon. An empty alias keeps the org name; \"Hide org\" shows only the repo name.")
                .font(.callout).foregroundStyle(.secondary)
            Table($store.layout.aliases) {
                TableColumn("Org") { $alias in
                    TextField("", text: $alias.org, prompt: Text("org"))
                        .onSubmit { alias.org = normalizeOrg(alias.org) }
                }
                TableColumn("Alias") { $alias in TextField("", text: $alias.alias, prompt: Text("short name")) }
                TableColumn("Hide org") { $alias in
                    Toggle("", isOn: $alias.hideOrg).labelsHidden()
                }
                .width(56)
                TableColumn("Icon") { $alias in
                    Picker("", selection: $alias.iconKind) {
                        ForEach(OrgIconKind.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                }
                TableColumn("Symbol or emoji") { $alias in
                    switch alias.iconKind {
                    case .symbol:
                        SymbolButton(symbol: $alias.iconValue)
                    case .emoji:
                        TextField("🚀  (⌃⌘Space for emoji)", text: $alias.iconValue)
                    case .none, .avatar:
                        Text("—").foregroundStyle(.tertiary)
                    }
                }
                TableColumn("") { $alias in
                    Button {
                        // read the id before the mutation, and remove after the table stops reading this row:
                        // reading `alias` inside removeAll reads the store it is changing (exclusivity crash)
                        let id = alias.id
                        DispatchQueue.main.async { store.layout.aliases.removeAll { $0.id == id } }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
                .width(24)
            }
            HStack {
                Button("Add Org") { store.layout.aliases.append(OrgAlias(org: "")) }
                    .disabled(store.layout.aliases.contains { $0.org.isEmpty })
                let missing = knownOrgs.filter { store.layout.alias(for: $0) == nil }
                if !missing.isEmpty {
                    Text("Your orgs:").font(.caption).foregroundStyle(.secondary)
                    ForEach(missing, id: \.self) { org in
                        Button(org) { store.layout.aliases.append(OrgAlias(org: org)) }.controlSize(.small)
                    }
                }
            }
            if let duplicate = duplicateOrg {
                Label("\(duplicate) is listed twice; only the first row is used.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(20)
    }

    private var knownOrgs: [String] {
        Array(Set((store.snapshot?.all ?? []).map(\.org))).sorted()
    }

    private var duplicateOrg: String? {
        var seen = Set<String>()
        for alias in store.layout.aliases where !alias.org.isEmpty {
            if !seen.insert(alias.org.lowercased()).inserted { return alias.org }
        }
        return nil
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Environment(Store.self) private var store
    @State private var token = ""
    @State private var hasToken = Token.hasKeychainToken
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section("Menu bar") {
                Picker("Style", selection: $store.settings.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                if store.settings.menuBarStyle == .text {
                    TextField("Title", text: $store.settings.titleTemplate)
                    Text("{review} PRs to review · {mine} your PRs · {ready} ready to merge · {new} new-activity symbol. Other text stays as it is.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("New activity symbol", text: $store.settings.newSymbol)
                } else {
                    Toggle("PRs waiting for your review (eye)", isOn: $store.settings.showReviewCount)
                    Toggle("Your open PRs (person)", isOn: $store.settings.showMineCount)
                    Toggle("Ready to merge (check)", isOn: $store.settings.showReadyCount)
                    Toggle("Hide counters at zero", isOn: $store.settings.hideZeroCounts)
                }
            }
            Section("Cards") {
                Picker("Commit", selection: $store.settings.commitStyle) {
                    ForEach(CommitStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                TextField("Separator between elements", text: $store.settings.separator, prompt: Text("none"))
                Stepper("Title lines: \(store.settings.titleMaxLines)", value: $store.settings.titleMaxLines, in: 1...6)
                Slider(value: $store.settings.popoverWidth, in: 320...720, step: 20) {
                    Text("Width: \(Int(store.settings.popoverWidth))")
                }
            }
            Section("Sections and filters") {
                Picker("Group PRs by", selection: $store.settings.groupBy) {
                    ForEach(GroupBy.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Review requested", isOn: $store.settings.showReview)
                Toggle("My pull requests", isOn: $store.settings.showMine)
                Toggle("Ready to merge (approved, green, mergeable)", isOn: $store.settings.showReady)
                Toggle("Include drafts", isOn: $store.settings.includeDrafts)
                Toggle("Include team review requests", isOn: $store.settings.teamRequests)
                Stepper("Refresh every \(store.settings.refreshMinutes) min", value: $store.settings.refreshMinutes, in: 1...60)
            }
            Section("GitHub") {
                HStack {
                    SecureField(hasToken ? "Token saved in Keychain" : "Empty: use the token of `gh auth login`", text: $token)
                    Button("Save") {
                        Token.save(token)
                        token = ""
                        hasToken = Token.hasKeychainToken
                        Task { await store.refresh() }
                    }
                    .disabled(token.isEmpty)
                    if hasToken {
                        Button("Remove") {
                            Token.save("")
                            hasToken = false
                            Task { await store.refresh() }
                        }
                    }
                }
                Text("Needs the repo scope. The token is stored in the macOS Keychain.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                Toggle("Open the dropdown with ⌥⌘P from any app", isOn: $store.settings.globalShortcut)
                Text("In the dropdown: ↑ ↓ move · ↩ open · ← → collapse or expand a section · H hide · M dismiss · C copy link · ⌘G group · ⌘R refresh · ⌘, settings · Esc close")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Picker("Appearance", selection: $store.settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // the revert after a failure fires onChange again; it must not wipe the error
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
