import AppKit
import SwiftUI

/// A button showing the chosen SF Symbol; it opens a searchable grid of symbols.
struct SymbolButton: View {
    @Binding var symbol: String
    @State private var picking = false

    var body: some View {
        Button {
            picking = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol.isEmpty ? "questionmark.square.dashed" : symbol).frame(width: 16)
                Text(symbol.isEmpty ? "Choose…" : symbol).lineLimit(1)
            }
        }
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            SymbolGrid(selection: $symbol) { picking = false }
        }
    }
}

private struct SymbolGrid: View {
    @Binding var selection: String
    let done: () -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search, or type any SF Symbol name", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 6), count: 9), spacing: 6) {
                    ForEach(results, id: \.self) { name in
                        Button {
                            selection = name
                            done()
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 15))
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(name == selection ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.05)))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }
            .frame(height: 260)
            if results.isEmpty {
                Text("No symbol named \"\(query)\"").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private var results: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Self.symbols }
        var found = Self.symbols.filter { $0.contains(q) }
        // any valid symbol name works, not only the ones in the list
        if !found.contains(q), NSImage(systemSymbolName: q, accessibilityDescription: nil) != nil { found.insert(q, at: 0) }
        return found
    }

    static let symbols: [String] = [
        "building.2", "building.columns", "briefcase", "house", "storefront", "hammer", "wrench.and.screwdriver",
        "gearshape", "gearshape.2", "cpu", "server.rack", "externaldrive", "cloud", "globe", "network",
        "antenna.radiowaves.left.and.right", "bolt", "flame", "leaf", "drop", "snowflake", "sun.max", "moon",
        "sparkles", "star", "heart", "flag", "bookmark", "tag", "folder", "tray", "archivebox", "shippingbox",
        "cube", "puzzlepiece", "gamecontroller", "dice", "cart", "bag", "creditcard", "dollarsign.circle",
        "chart.bar", "chart.line.uptrend.xyaxis", "chart.pie", "person", "person.2", "person.3", "figure.walk",
        "graduationcap", "book", "books.vertical", "newspaper", "doc.text", "pencil", "paintbrush", "paintpalette",
        "camera", "photo", "music.note", "film", "tv", "headphones", "airplane", "car", "bicycle", "tram",
        "ferry", "map", "mappin", "location", "ladybug", "ant", "tortoise", "hare", "pawprint", "bird", "fish",
        "lock", "key", "shield", "eye", "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces",
        "number", "function", "atom", "testtube.2", "flask", "cross.case", "stethoscope", "pills", "crown",
        "trophy", "rosette", "gift", "balloon", "party.popper", "theatermasks", "envelope", "bubble.left.and.bubble.right",
        "bell", "calendar", "clock", "timer", "lightbulb", "battery.100", "wifi", "link", "paperplane",
        "rocket", "scope", "target", "circle.hexagongrid", "square.stack.3d.up", "point.3.connected.trianglepath.dotted",
    ].filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
}
