import PRCore
import SwiftUI

/// Color of a calendar day by its level (0 none … 4 most): GitHub's contribution colors, light and dark.
func activityColor(_ level: Int, dark: Bool) -> Color {
    let light: [UInt32] = [0xEBEDF0, 0x9BE9A8, 0x40C463, 0x30A14E, 0x216E39]
    let night: [UInt32] = [0x2D333B, 0x0E4429, 0x006D32, 0x26A641, 0x39D353]
    // an empty day is a soft shade of the menu background: a fixed near-white glares on the grey menu
    if level <= 0 { return Color.primary.opacity(dark ? 0.12 : 0.1) }
    let hex = (dark ? night : light)[min(level, 4)]
    return Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
}

private let dayLabel: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE, MMM d"
    return f
}()

private let monthLabel: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM"
    return f
}()

/// The top row of the dropdown: the last 7 days as colored squares. A click expands the full calendar.
struct ActivityRow: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme

    private var expanded: Bool { store.activityExpanded }
    private var hovered: Bool { store.selection == "row:activity" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActivityHeader(week: Array(store.calendar.suffix(7)))
            if expanded {
                ContributionCalendar()
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? Color.primary.opacity(0.1) : .clear))
        .opacity(store.calendar.isEmpty ? 0 : 1)
        .frame(height: store.calendar.isEmpty ? 0 : nil)
    }
}

/// "Activity", the week's squares and total, the Insights icon and the chevron.
private struct ActivityHeader: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    let week: [ContributionDay]

    private var total: Int { week.map(\.count).reduce(0, +) }
    private var expanded: Bool { store.activityExpanded }
    private var hovered: Bool { store.selection == "row:activity" }

    var body: some View {
        HStack(spacing: 8) {
            Text("Activity").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.7))
            squares
            Text(verbatim: "\(total) this week")
                .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.85))
            Spacer()
            insightsButton
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .foregroundStyle(Color.primary.opacity(hovered ? 0.85 : 0.45))
        }
        .contentShape(Rectangle())
        .onHover { store.hover("row:activity", $0) }
        .pointingHand()
        .onTapGesture { store.activityExpanded.toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity: \(total) contributions in the last 7 days")
        .accessibilityHint(expanded ? "Hides the calendar" : "Shows the calendar")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { store.activityExpanded.toggle() }
        .accessibilityAction(named: "Insights") { InsightsWindow.shared.show(store) }
    }

    private var squares: some View {
        HStack(spacing: 3) {
            ForEach(week) { day in
                RoundedRectangle(cornerRadius: 3)
                    .fill(activityColor(day.level, dark: scheme == .dark))
                    .frame(width: 13, height: 13)
                    .help(dayHelp(day))
            }
        }
    }

    private var insightsButton: some View {
        Button {
            InsightsWindow.shared.show(store)
        } label: {
            Image(systemName: "chart.bar.xaxis").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(0.65))
        .help("Insights")
        .pointingHand()
    }
}

func dayHelp(_ day: ContributionDay) -> String {
    "\(dayLabel.string(from: day.date)): \(day.count) contribution\(day.count == 1 ? "" : "s")"
}

/// The contribution calendar as week columns; scrolling to the left edge loads the year before.
struct ContributionCalendar: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var scheme
    private let cell: CGFloat = 10
    private let gap: CGFloat = 2

    var body: some View {
        let weeks = calendarWeeks(store.calendar)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: gap) {
                    // an older year loads only on request, so the calendar never moves by itself
                    Button {
                        let anchor = weeks.first?.first?.date
                        Task {
                            await store.loadOlderCalendar()
                            // stay on the week that was first before the older year came in
                            if let anchor { proxy.scrollTo(anchor, anchor: .leading) }
                        }
                    } label: {
                        Group {
                            if store.calendarLoadingOlder {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .frame(width: 18, height: 7 * (cell + gap) + 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .help("Load the year before")
                    .pointingHand()
                    ForEach(Array(weeks.enumerated()), id: \.element.first!.date) { index, week in
                        VStack(spacing: gap) {
                            // month name above the first week of a month
                            Text(isMonthStart(week, previous: index > 0 ? weeks[index - 1] : nil) ? monthLabel.string(from: week[0].date) : " ")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.primary.opacity(0.75))
                                .fixedSize()
                                .frame(width: cell, height: 10, alignment: .leading)
                            if index == 0 {
                                // the first column can start mid-week: pad the missing days
                                ForEach(0..<(7 - week.count), id: \.self) { _ in Color.clear.frame(width: cell, height: cell) }
                            }
                            ForEach(week) { day in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(activityColor(day.level, dark: scheme == .dark))
                                    .frame(width: cell, height: cell)
                                    .help("\(dayLabel.string(from: day.date)): \(day.count) contribution\(day.count == 1 ? "" : "s")")
                            }
                        }
                        .id(week[0].date)
                    }
                }
                .padding(.vertical, 2)
            }
            .onAppear {
                // open on today, once
                if let last = weeks.last?.first?.date { proxy.scrollTo(last, anchor: .trailing) }
            }
        }
        HStack(spacing: 4) {
            Text(verbatim: "\(store.calendar.suffix(365).map(\.count).reduce(0, +)) contributions in the last year")
            Spacer()
            Text("Less")
            ForEach(0..<5) { level in
                RoundedRectangle(cornerRadius: 2).fill(activityColor(level, dark: scheme == .dark)).frame(width: 9, height: 9)
            }
            Text("More")
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.primary.opacity(0.75))
    }

    private func isMonthStart(_ week: [ContributionDay], previous: [ContributionDay]?) -> Bool {
        guard let previous, let first = week.first, let before = previous.first else { return false }
        return Calendar.current.component(.month, from: first.date) != Calendar.current.component(.month, from: before.date)
    }
}
