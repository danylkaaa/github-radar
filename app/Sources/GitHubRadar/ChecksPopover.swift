import AppKit
import PRCore
import SwiftUI

/// Shows `content` in a popover while the pointer rests on the label or on the popover.
struct HoverPopover<Label: View, Content: View>: View {
    var enabled = true
    @ViewBuilder let label: Label
    @ViewBuilder let content: () -> Content
    @State private var showing = false
    @State private var overLabel = false
    @State private var overPopover = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        label
            .onHover { overLabel = $0; schedule() }
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                content()
                    // a popover inherits the card's white hover text; it has its own colors
                    .foregroundStyle(Color.primary)
                    .onHover { overPopover = $0; schedule() }
                    // same material as the dropdown; it overflows so the popover arrow is covered too
                    .background(MenuBackground().padding(-40))
            }
    }

    /// Opens after a short rest, like a tooltip; closes shortly after the pointer leaves both.
    private func schedule() {
        pending?.cancel()
        let wanted = overLabel || overPopover
        guard wanted != showing, enabled else { return }
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: wanted ? 350_000_000 : 250_000_000)
            guard !Task.isCancelled else { return }
            showing = overLabel || overPopover
        }
    }
}

struct ChecksList: View {
    let pr: PullRequest
    private let maxRows = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.55))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
            ForEach(pr.checks.prefix(maxRows)) { check in
                CheckRow(check: check)
            }
            if pr.checkCount > maxRows {
                Text("\(pr.checkCount - maxRows) more")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
            }
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1).padding(.horizontal, 9).padding(.vertical, 5)
            CheckRow(check: Check(name: "Open checks on GitHub", state: .skipped,
                                  url: pr.url.appendingPathComponent("checks")), plain: true)
        }
        .padding(5)
        .frame(width: 380)
    }

    private var summary: String {
        let counts = Dictionary(grouping: pr.checks, by: \.state).mapValues(\.count)
        let parts: [(Check.State, String)] = [(.failed, "failed"), (.running, "running"), (.passed, "passed"), (.skipped, "skipped")]
        return parts.compactMap { state, word in counts[state].map { "\($0) \(word)" } }.joined(separator: " · ")
    }
}

private struct CheckRow: View {
    let check: Check
    var plain = false
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            icon.frame(width: 16)
            Text(check.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if let duration = check.duration, check.state != .skipped {
                Text(formatDuration(duration)).opacity(0.72).monospacedDigit()
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(hovered ? Color.white : Color.primary)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 && check.url != nil }
        .onTapGesture {
            guard let url = check.url else { return }
            closeDropdown()
            NSWorkspace.shared.open(url)
        }
    }

    @ViewBuilder
    private var icon: some View {
        if plain {
            Image(systemName: "arrow.up.right.square")
        } else {
            switch check.state {
            case .running: Spinner(highlighted: hovered)
            case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(hovered ? .white : .red)
            case .passed: Image(systemName: "checkmark.circle.fill").foregroundStyle(hovered ? .white : .green)
            case .skipped: Image(systemName: "minus.circle").foregroundStyle(hovered ? Color.white : Color.primary.opacity(0.72))
            }
        }
    }
}

/// The menu material, for popovers that should look like the dropdown.
struct MenuBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .menu
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}
