import AppKit

// AppKit start instead of a SwiftUI App: a SwiftUI app whose only scene is Settings opens that window at launch
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
