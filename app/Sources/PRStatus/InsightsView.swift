import AppKit
import Charts
import PRCore
import SwiftUI

/// The Insights window, created when asked for and released when closed.
@MainActor
final class InsightsWindow: NSObject, NSWindowDelegate {
    static let shared = InsightsWindow()
    private var window: NSWindow?

    func show(_ store: Store) {
        closeDropdown()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: InsightsView().environment(store)))
            window.title = "PR Status Insights"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 760, height: 720))
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

struct InsightsView: View {
    @Environment(Store.self) private var store
    @State private var period: InsightsPeriod = .month

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Picker("Period", selection: $period) {
                    ForEach(InsightsPeriod.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)
                Spacer()
                if store.insightsLoading.contains(period) {
                    ProgressView().controlSize(.small)
                }
                Button {
                    Task { await store.loadInsights(period, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload")
            }
            .padding(16)
            Divider()
            ScrollView {
                if let insights = store.insights[period] {
                    content(insights).padding(16)
                } else if let error = store.insightsError, !store.insightsLoading.contains(period) {
                    Label(error, systemImage: "exclamationmark.triangle").padding(16)
                } else {
                    ProgressView("Loading your activity…").frame(maxWidth: .infinity, minHeight: 300)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 520)
        // not tied to the view: closing or redrawing the window must not cancel a running load
        .onAppear { Task { await store.loadInsights(period) } }
        .onChange(of: period) { _, new in Task { await store.loadInsights(new) } }
    }

    // split into small views: one large body is too slow to type-check for older Swift compilers
    private func content(_ insights: Insights) -> some View {
        let dates = insights.commits.map(\.date)
        return VStack(alignment: .leading, spacing: 16) {
            Totals(insights: insights)
            HStack(alignment: .top, spacing: 12) {
                Panel(title: "When you commit, by hour") { HourChart(hours: hourHistogram(dates)) }
                Panel(title: "By weekday") { WeekdayChart(days: weekdayHistogram(dates)) }
                    .frame(width: 260)
            }
            Panel(title: "Worked on most (commits)") { ReposChart(repos: topRepos(insights.commits), total: insights.commits.count) }
            HStack(alignment: .top, spacing: 12) {
                Panel(title: "Time to merge by org") { MergeTable(rows: mergeStats(insights.merged, by: \.org)) }
                Panel(title: "Time to merge by repo") { MergeTable(rows: mergeStats(insights.merged, by: \.repo)) }
            }
        }
    }
}

private struct Totals: View {
    let insights: Insights

    var body: some View {
        let overall = mergeStats(insights.merged)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                StatTile(title: "Commits", value: "\(insights.commits.count)\(insights.commitsCapped ? "+" : "")")
                StatTile(title: "PRs merged", value: "\(insights.merged.count)")
                StatTile(title: "Avg time to merge", value: overall.map { formatSpan($0.average) } ?? "—")
                StatTile(title: "Median time to merge", value: overall.map { formatSpan($0.median) } ?? "—")
            }
            if insights.commitsCapped {
                Text("GitHub's commit search returns at most 1000 commits; the charts use the latest 1000 of this period.")
                    .font(.caption).foregroundStyle(Color.primary.opacity(0.75))
            }
        }
    }
}

private struct HourChart: View {
    let hours: [Int]
    @State private var hover: Int?

    var body: some View {
        Chart {
            ForEach(Array(hours.enumerated()), id: \.offset) { hour, count in
                BarMark(x: .value("Hour", hour), y: .value("Commits", count))
                    .foregroundStyle(color(hour))
            }
            if let hour = hover, hours.indices.contains(hour) {
                RuleMark(x: .value("Hour", hour))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartPopup(title: String(format: "%02d:00–%02d:59", hour, hour), value: "\(hours[hour]) commits")
                    }
            }
        }
        .chartXSelection(value: $hover)
        .chartXScale(domain: -0.5...23.5)
        .chartXAxis { AxisMarks(values: [0, 6, 12, 18]) { _ in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.18))
            AxisTick().foregroundStyle(Color.primary.opacity(0.3))
            AxisValueLabel().foregroundStyle(Color.primary.opacity(0.85)).font(.system(size: 11))
        } }
        .chartYAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.18))
            AxisTick().foregroundStyle(Color.primary.opacity(0.3))
            AxisValueLabel().foregroundStyle(Color.primary.opacity(0.85)).font(.system(size: 11))
        } }
        .frame(height: 150)
    }

    private func color(_ hour: Int) -> Color {
        hover == nil || hover == hour ? Color.accentColor : Color.accentColor.opacity(0.35)
    }
}

private struct WeekdayChart: View {
    let days: [Int]
    @State private var hover: String?
    private let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        Chart {
            ForEach(Array(days.enumerated()), id: \.offset) { day, count in
                BarMark(x: .value("Day", names[day]), y: .value("Commits", count))
                    .foregroundStyle(color(names[day]))
            }
            if let day = hover, let index = names.firstIndex(of: day) {
                RuleMark(x: .value("Day", day))
                    .foregroundStyle(Color.primary.opacity(0.25))
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartPopup(title: day, value: "\(days[index]) commits")
                    }
            }
        }
        .chartXSelection(value: $hover)
        .chartXAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.18))
            AxisTick().foregroundStyle(Color.primary.opacity(0.3))
            AxisValueLabel().foregroundStyle(Color.primary.opacity(0.85)).font(.system(size: 11))
        } }
        .chartYAxis { AxisMarks { _ in
            AxisGridLine().foregroundStyle(Color.primary.opacity(0.18))
            AxisTick().foregroundStyle(Color.primary.opacity(0.3))
            AxisValueLabel().foregroundStyle(Color.primary.opacity(0.85)).font(.system(size: 11))
        } }
        .frame(height: 150)
    }

    private func color(_ day: String) -> Color {
        hover == nil || hover == day ? Color.green : Color.green.opacity(0.35)
    }
}

private struct ReposChart: View {
    let repos: [(repo: String, commits: Int)]
    let total: Int
    @State private var hover: String?

    var body: some View {
        if repos.isEmpty {
            Text("No commits in this period").foregroundStyle(Color.primary.opacity(0.75))
        } else {
            Chart(repos, id: \.repo) { item in
                BarMark(x: .value("Commits", item.commits), y: .value("Repo", item.repo))
                    .foregroundStyle(hover == nil || hover == item.repo ? Color.orange : Color.orange.opacity(0.35))
                    .annotation(position: .trailing) {
                        Text(label(item))
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.primary.opacity(0.85))
                    }
            }
            .chartYSelection(value: $hover)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Color.primary).font(.system(size: 12)) } }
            .frame(height: CGFloat(repos.count) * 26 + 10)
        }
    }

    private func label(_ item: (repo: String, commits: Int)) -> String {
        guard hover == item.repo else { return "\(item.commits)" }
        let share = Int((Double(item.commits) / Double(max(1, total)) * 100).rounded())
        return "\(item.commits) commits · \(share)%"
    }
}

private struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.primary.opacity(0.75))
            Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit()).foregroundStyle(Color.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
    }
}

private struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.3).foregroundStyle(Color.primary.opacity(0.75))
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
    }
}

private struct MergeTable: View {
    let rows: [(key: String, stats: MergeStats)]

    var body: some View {
        if rows.isEmpty {
            Text("No merged PRs in this period").foregroundStyle(Color.primary.opacity(0.75))
        } else {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text("PRs").gridColumnAlignment(.trailing)
                    Text("Avg").gridColumnAlignment(.trailing)
                    Text("Median").gridColumnAlignment(.trailing)
                }
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.primary.opacity(0.75))
                ForEach(rows.prefix(10), id: \.key) { row in
                    GridRow {
                        Text(row.key).lineLimit(1).truncationMode(.middle)
                        Text("\(row.stats.count)")
                        Text(formatSpan(row.stats.average))
                        Text(formatSpan(row.stats.median))
                    }
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color.primary)
                }
            }
        }
    }
}

/// The value of the hovered bar, in a small popup above it.
private struct ChartPopup: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.75))
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15)))
    }
}
