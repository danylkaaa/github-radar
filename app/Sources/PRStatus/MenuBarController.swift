import AppKit
import Observation
import PRCore
import SwiftUI

/// The status item and its dropdown panel, drawn like a native menu (menu material, 12 pt corners, shadow).
@MainActor
final class MenuBarController: NSObject {
    static private(set) var shared: MenuBarController?

    private let store: Store
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var panel: DropdownPanel?
    private var outsideClickMonitor: Any?
    private var lastClose = Date.distantPast
    private lazy var hotKey = HotKey { [weak self] in self?.toggleFromShortcut() }
    private let cornerRadius: CGFloat = 12

    init(store: Store) {
        self.store = store
        super.init()
        Self.shared = self
        if let button = statusItem.button {
            button.image = menuBarIcon
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(toggle)
        }
        trackTitle()
        trackShortcut()

    }

    /// Redraws the status item whenever anything it shows changes.
    private func trackTitle() {
        withObservationTracking {
            _ = (store.title, store.tooltip, store.dotAttention, store.menuBarCounters.map(\.count), store.settings, store.error)
        } onChange: { [weak self] in
            Task { @MainActor in self?.trackTitle() }
        }
        render()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        button.toolTip = store.tooltip
        button.imagePosition = .imageLeading
        if store.settings.menuBarStyle == .text || store.snapshot == nil {
            button.image = menuBarIcon
            let title = store.title
            button.attributedTitle = styledTitle(title.isEmpty ? "" : " \(title)")
            return
        }
        let dot = store.dotAttention.map { NSColor($0.color) }
        button.image = store.settings.menuBarStyle == .status && dot != nil ? MenuBarTitle.tintedIcon(dot!) : menuBarIcon
        button.attributedTitle = MenuBarTitle.make(
            style: store.settings.menuBarStyle,
            counters: store.menuBarCounters,
            dot: dot,
            failed: store.error != nil
        )
    }

    /// The menu bar text, with the new-activity symbol in the accent color like an unread dot.
    private func styledTitle(_ title: String) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let text = NSMutableAttributedString(string: title, attributes: [.font: font])
        let symbol = store.settings.newSymbol
        if let attention = store.dotAttention, !symbol.isEmpty, let range = title.range(of: symbol, options: .backwards) {
            text.addAttribute(.foregroundColor, value: NSColor(attention.color), range: NSRange(range, in: title))
        }
        return text
    }

    /// The status item's frame on screen (top-left origin), for screenshots.
    var statusItemScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window, let screen = window.screen else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    private func trackShortcut() {
        let enabled = withObservationTracking { store.settings.globalShortcut } onChange: { [weak self] in
            Task { @MainActor in self?.trackShortcut() }
        }
        hotKey.setEnabled(enabled)
    }

    private func toggleFromShortcut() {
        if panel?.isVisible == true {
            close()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            open()
        }
    }

    @objc func toggle() {
        // a click on the status item first closes the panel via resignKey; do not reopen it at once
        if panel?.isVisible == true || Date.now.timeIntervalSince(lastClose) < 0.3 {
            close()
        } else {
            open()
        }
    }

    func open() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: store.settings.popoverWidth, height: 300)
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var x = anchor.minX
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - 5 - size.height, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)
        button.highlight(true)
        if !CommandLine.arguments.contains("--pin") {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
        }
    }

    func close() {
        if panel?.isVisible == true { lastClose = .now }
        panel?.orderOut(nil)
        statusItem.button?.highlight(false)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }

    private func makePanel() -> DropdownPanel {
        let panel = DropdownPanel(
            contentRect: NSRect(x: 0, y: 0, width: store.settings.popoverWidth, height: 300),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // --pin keeps the dropdown open when another app takes focus, for screenshots
        if !CommandLine.arguments.contains("--pin") {
            panel.onResignKey = { [weak self] in self?.close() }
        }

        let material = NSVisualEffectView()
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = .roundedMask(radius: cornerRadius)

        let hosting = NSHostingView(rootView: PopoverView().environment(store))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: material.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        panel.contentView = material
        return panel
    }
}

/// A borderless panel that can take key status (for ⌘R, ⌘, and ⌘Q) and closes when it loses it.
final class DropdownPanel: NSPanel {
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        // a popover of the panel (CI checks) taking key status must not close the dropdown
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.keyWindow?.parent !== self else { return }
            self.onResignKey?()
        }
    }

    override func cancelOperation(_: Any?) {
        onResignKey?()
    }
}

extension NSImage {
    /// A stretchable rounded-rect mask for NSVisualEffectView.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

let menuBarIcon: NSImage = {
    let image = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png").flatMap(NSImage.init(contentsOf:))
        ?? NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)!
    image.size = NSSize(width: 16, height: 16)
    image.isTemplate = true
    return image
}()

extension Attention {
    var color: Color {
        switch self {
        case .fix: .red
        case .waiting: .yellow
        case .activity: .blue
        case .good: .green
        }
    }
}
