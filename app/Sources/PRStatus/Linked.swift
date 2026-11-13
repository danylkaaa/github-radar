import AppKit
import SwiftUI

/// Makes a view a link: pointing-hand cursor and underline on hover, a click closes the dropdown and opens `url`.
struct Linked: ViewModifier {
    let url: URL?
    @State private var hovered = false

    func body(content: Content) -> some View {
        if let url {
            Button {
                closeDropdown()
                NSWorkspace.shared.open(url)
            } label: {
                content.underline(hovered).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .pointingHand()
            .help(url.absoluteString)
        } else {
            content
        }
    }
}

extension View {
    func linked(_ url: URL?) -> some View { modifier(Linked(url: url)) }
}

func profileURL(_ login: String) -> URL? { URL(string: "https://github.com/\(login)") }

extension View {
    /// The pointing-hand cursor while the pointer is over a clickable view.
    /// `set()` instead of push/pop: a missed pop would leave the hand stuck.
    func pointingHand() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}
