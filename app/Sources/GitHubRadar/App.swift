import AppKit
import PRCore
import SwiftUI

/// The settings window, created when asked for and released when closed, so it costs no memory while hidden.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?

    func show(_ store: Store) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environment(store)))
            window.title = "GitHub Radar Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}

/// Without a main menu, ⌘C/⌘V/⌘A/⌘Z do nothing in text fields.
@MainActor
private func makeMainMenu() -> NSMenu {
    let main = NSMenu()
    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(.separator())
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    editItem.submenu = edit
    let windowItem = NSMenuItem()
    main.addItem(windowItem)
    let windowMenu = NSMenu(title: "Window")
    windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = windowMenu
    return main
}

/// Writes one PNG per commit style: a sample card on a light and a dark menu.
@MainActor
private func renderCommitStyles(to folder: URL) {
    let pr = Samples.prs()[0]
    for style in CommitStyle.allCases {
        var settings = AppSettings()
        settings.commitStyle = style
        var layout = CardLayout.default
        if style == .full {
            // its own line, right under the title
            layout.elements = layout.elements.map { element in
                var element = element
                if element.id == .commit { element.line = 3 } else if element.line >= 3 { element.line += 1 }
                return element
            }
        }
        let cards = VStack(spacing: 0) {
            ForEach([false, true], id: \.self) { dark in
                CardView(pr: pr, layout: layout, settings: settings, now: .now)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(width: 420)
                    .background(dark ? Color(white: 0.2) : Color(white: 0.94))
                    .environment(\.colorScheme, dark ? .dark : .light)
            }
        }
        let renderer = ImageRenderer(content: cards)
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: folder.appendingPathComponent("commit-\(style.rawValue).png"))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private var menuBar: MenuBarController?
    private var debugWindows: [NSWindow] = []

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = makeMainMenu()
        menuBar = MenuBarController(store: store)
        store.start()
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
        // --show-popover / --show-settings / --show-details open the views at launch, for screenshots
        let args = CommandLine.arguments
        if args.contains("--show-popover") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.menuBar?.open() }
        }
        if let i = args.firstIndex(of: "--render-commit-styles"), i + 1 < args.count {
            renderCommitStyles(to: URL(fileURLWithPath: args[i + 1]))
            NSApp.terminate(nil)
        }
        if args.contains("--show-details") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                guard let pr = self.store.snapshot?.all.max(by: { $0.comments + $0.reviewerList.count < $1.comments + $1.reviewerList.count })
                else { return }
                let all = self.store.snapshot?.all ?? []
                let view = HStack(alignment: .top) {
                    ChecksList(pr: pr)
                    VStack(alignment: .leading) { ForEach(all) { CommitsList(pr: $0) } }
                    VStack(alignment: .leading) { ForEach(all.filter { !$0.conversation.isEmpty }) { CommentsList(pr: $0) } }
                }
                let window = NSWindow(contentViewController: NSHostingController(rootView: view))
                window.title = "GitHub Radar details"
                window.makeKeyAndOrderFront(nil)
                self.debugWindows.append(window)
            }
        }
        if args.contains("--show-settings") {
            SettingsWindow.shared.show(store)
        }
        if args.contains("--expand-activity") { store.activityExpanded = true }
        if let i = args.firstIndex(of: "--status-frame-file"), i + 1 < args.count {
            let path = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if let f = self.menuBar?.statusItemScreenFrame {
                    try? "\(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height))".write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
        }
        if args.contains("--show-insights") {
            InsightsWindow.shared.show(store)
        }
    }
}
