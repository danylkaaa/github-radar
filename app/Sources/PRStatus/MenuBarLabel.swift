import AppKit
import PRCore
import SwiftUI

/// One counter of the menu bar item.
struct MenuBarCounter {
    let id: String
    let symbol: String
    let count: Int
    /// Color when the count is above zero; nil keeps the menu bar text color.
    let tint: NSColor?
}

extension Store {
    /// The counters the settings ask for, in menu bar order.
    var menuBarCounters: [MenuBarCounter] {
        guard let snapshot = shownSnapshot else { return [] }
        let all: [(Bool, MenuBarCounter)] = [
            (settings.showReviewCount, .init(id: "review", symbol: "eye", count: snapshot.review.count, tint: .systemOrange)),
            (settings.showMineCount, .init(id: "mine", symbol: "person", count: snapshot.mine.count, tint: nil)),
            (settings.showReadyCount, .init(id: "ready", symbol: "checkmark.circle", count: snapshot.ready.count, tint: .systemGreen)),
        ]
        return all.filter { $0.0 && (!settings.hideZeroCounts || $0.1.count > 0) }.map(\.1)
    }
}

/// The menu bar text as styled text and symbols. Drawn by AppKit like any status item title:
/// rendering SwiftUI to an image here cost about 220 MB at the first draw.
enum MenuBarTitle {
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)

    static func make(style: MenuBarStyle, counters: [MenuBarCounter], dot: NSColor?, failed: Bool) -> NSAttributedString {
        let text = NSMutableAttributedString()
        text.append(plain(" "))
        switch style {
        case .numbers:
            for (index, counter) in counters.enumerated() {
                if index > 0 { text.append(plain("/", color: .secondaryLabelColor)) }
                text.append(plain("\(counter.count)", color: color(counter)))
            }
        case .icons:
            for (index, counter) in counters.enumerated() {
                if index > 0 { text.append(plain("  ")) }
                text.append(symbol(counter.symbol, color: counter.tint ?? .labelColor))
                text.append(plain(" \(counter.count)", color: color(counter)))
            }
        case .status:
            let needed = counters.filter { $0.id != "mine" }.map(\.count).reduce(0, +)
            if needed > 0 { text.append(plain("\(needed)")) }
        case .text:
            break
        }
        if let dot, style != .status {
            text.append(plain(" "))
            text.append(symbol("circle.fill", color: dot, size: 6))
        }
        if failed {
            text.append(plain(" "))
            text.append(symbol("exclamationmark.triangle.fill", color: .systemOrange, size: 10))
        }
        return text
    }

    private static func color(_ counter: MenuBarCounter) -> NSColor {
        // each position keeps its color, zero too, so the numbers are told apart by color
        counter.tint ?? .labelColor
    }

    private static func plain(_ string: String, color: NSColor? = nil) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .baselineOffset: 0]
        if let color { attributes[.foregroundColor] = color }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private static func symbol(_ name: String, color: NSColor, size: CGFloat = 11) -> NSAttributedString {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return NSAttributedString()
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        // centered on the digits
        attachment.bounds = NSRect(x: 0, y: (font.capHeight - image.size.height) / 2, width: image.size.width, height: image.size.height)
        return NSAttributedString(attachment: attachment)
    }

    /// The PR icon in one color, for the status style.
    static func tintedIcon(_ color: NSColor) -> NSImage {
        let image = NSImage(size: menuBarIcon.size, flipped: false) { rect in
            menuBarIcon.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }
}
