import AppKit
import PRCore
import SwiftUI

/// One PR as a card: the layout's lines, each a row of elements.
struct CardView: View {
    static let trailing: Set<ElementID> = [.updated, .participants]

    /// The commit element shows its message, which must truncate instead of widening the card.
    private var commitHasMessage: Bool { settings.commitStyle == .full || settings.commitStyle == .hashAndMessage }

    /// The change an element shows, if any.
    static func change(for id: ElementID) -> Change? {
        switch id {
        case .ci: .ci
        case .comments: .comments
        case .reviews: .reviews
        default: nil
        }
    }

    let pr: PullRequest
    let layout: CardLayout
    let settings: AppSettings
    /// Hovered in the dropdown: everything turns white on the accent color, as in a native menu.
    var highlighted = false
    /// Hides the right side of the first line, where the dropdown shows its hover buttons.
    var hideFirstLineTrailing = false
    var now = Date()

    var body: some View {
        let lines = layout.lines.map { $0.filter { ElementView.hasContent($0.id, pr: pr, settings: settings) } }.filter { !$0.isEmpty }
        VStack(alignment: .leading, spacing: 4) {
            if lines.isEmpty {
                // every element hidden or empty: still show which PR this is
                Text(layout.repoLabel(pr)).font(.system(size: 13))
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                // last update and participants sit at the right edge of their line
                let left = line.filter { !Self.trailing.contains($0.id) }
                let right = line.filter { Self.trailing.contains($0.id) }
                HStack(alignment: .center, spacing: 6) {
                    if left.contains(where: { $0.id == .title || ($0.id == .commit && commitHasMessage) }) {
                        // the title wraps and a commit message truncates inside the card width
                        HStack(alignment: .firstTextBaseline, spacing: 6) { elements(left) }
                    } else {
                        // other elements never break inside; the whole element moves to the next row
                        FlowLayout(spacing: 6) { elements(left) }
                    }
                    if !right.isEmpty {
                        Spacer(minLength: 6)
                        HStack(spacing: 6) { elements(right) }
                            .fixedSize()
                            // the hover buttons of the dropdown take this place
                            .opacity(index == 0 && hideFirstLineTrailing ? 0 : 1)
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(highlighted ? Color.white : Color.primary.opacity(0.8))
                .padding(.trailing, index == 0 && hideFirstLineTrailing && right.isEmpty ? 44 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func elements(_ line: [LayoutElement]) -> some View {
        ForEach(Array(line.enumerated()), id: \.element.id) { index, element in
            if index > 0, !settings.separator.isEmpty {
                Text(settings.separator).opacity(0.6)
            }
            if element.id == .title || (element.id == .commit && commitHasMessage) {
                ElementView(element: element, pr: pr, layout: layout, settings: settings, highlighted: highlighted, now: now)
            } else {
                ElementView(element: element, pr: pr, layout: layout, settings: settings, highlighted: highlighted, now: now)
                    .fixedSize()
                    .modifier(ChangedMark(highlighted: highlighted,
                                          active: Self.change(for: element.id).map(pr.changes.contains) ?? false))
            }
        }
    }
}

struct ElementView: View {
    let element: LayoutElement
    let pr: PullRequest
    let layout: CardLayout
    let settings: AppSettings
    let highlighted: Bool
    let now: Date

    static func hasContent(_ id: ElementID, pr: PullRequest, settings: AppSettings) -> Bool {
        switch id {
        case .new: pr.isNew
        case .author: !pr.mine
        case .draft: pr.isDraft
        case .comments: pr.comments > 0
        case .participants: pr.participantCount > 0
        case .commit: !pr.activity.oid.isEmpty
        case .size: pr.additions + pr.deletions > 0
        default: true
        }
    }

    var body: some View {
        switch element.id {
        case .title:
            PRTitle(text: pr.title, maxLines: settings.titleMaxLines, highlighted: highlighted)
        case .new:
            let what = pr.changes.map(\.label).sorted().joined(separator: ", ")
            styled(icon: Image(systemName: "circle.fill").font(.system(size: 7))
                .foregroundStyle(highlighted ? Color.white : pr.attention.color),
                   text: settings.newSymbol)
                .help(what.isEmpty ? "New to you" : "New since you looked: \(what)")
        case .repo:
            // an icon picked for the org shows even when the element is set to text only
            Group {
                switch settings.groupBy {
                // the group header already names the repo or org
                case .repo: Text("#\(pr.number)")
                case .org: Text("\(pr.repoName)#\(pr.number)")
                case .none:
                    if element.style == .text, let kind = layout.alias(for: pr.org)?.iconKind, kind == .symbol || kind == .emoji {
                        HStack(spacing: 3) { orgIcon; Text(layout.repoLabel(pr)) }
                    } else {
                        styled(icon: orgIcon, text: layout.repoLabel(pr))
                    }
                }
            }
            .linked(URL(string: "https://github.com/\(pr.repo)"))
        case .commit:
            HoverPopover {
                CommitLink(pr: pr, style: element.style, commitStyle: settings.commitStyle, highlighted: highlighted, now: now)
            } content: {
                CommitsList(pr: pr)
            }
        case .size:
            HStack(spacing: 4) {
                if element.style != .text { Image(systemName: "plusminus") }
                Text(verbatim: "+\(pr.additions)")
                Text(verbatim: "−\(pr.deletions)")
            }
            .font(.system(size: 12).monospacedDigit())
            .linked(pr.url.appendingPathComponent("files"))
        case .updated:
            styled(icon: Image(systemName: "clock"), text: "\(relativeAge(pr.updatedAt, now: now)) ago")
        case .ci:
            HoverPopover(enabled: !pr.checks.isEmpty) {
                // the icon color tells the result, so the text says only "CI" unless there is no icon
                styled(icon: ciIcon, text: element.style == .text || pr.ci == .none ? pr.ci.label : "CI")
            } content: {
                ChecksList(pr: pr)
            }
        case .reviews:
            HoverPopover {
                if element.style == .text {
                    Text(pr.reviewLabel)
                } else if !deciders.isEmpty {
                    // the icon tells the decision, the avatars who made it
                    HStack(spacing: 4) {
                        reviewIcon
                        if element.style == .iconAndText {
                            AvatarStack(people: deciders, total: deciders.count, highlighted: highlighted)
                        }
                    }
                } else {
                    reviewIcon.help(pr.reviewLabel)
                }
            } content: {
                ReviewersList(pr: pr)
            }
        case .comments:
            HoverPopover {
                styled(icon: Image(systemName: pr.newComments > 0 ? "bubble.left.fill" : "bubble.left"),
                       text: commentsText)
            } content: {
                CommentsList(pr: pr)
            }
        case .author:
            styled(icon: Image(systemName: "person"), text: "@\(pr.author)").linked(profileURL(pr.author))
        case .draft:
            if element.style == .icon {
                Image(systemName: "pencil.circle").help("Draft")
            } else {
                // a small label, like GitHub's draft badge
                Text("Draft")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().strokeBorder(highlighted ? Color.white.opacity(0.7) : Color.primary.opacity(0.35)))
            }
        case .participants:
            let people = pr.people(includeViewer: true)
            if element.style == .text {
                Text(people.shown.prefix(3).map { "@\($0.login)" }.joined(separator: ", ")
                    + (people.total > 3 ? " +\(people.total - 3)" : ""))
            } else {
                HoverPopover {
                    AvatarStack(people: people.shown, total: people.total, highlighted: highlighted)
                } content: {
                    PeopleList(pr: pr)
                }
            }
        }
    }

    /// Who asked for changes, else who approved; people who only commented are left out.
    private var deciders: [Participant] {
        let state: Reviewer.State = pr.changesRequested ? .changesRequested : .approved
        return pr.reviewerList.filter { $0.state == state }.map { Participant(login: $0.login, avatarURL: $0.avatarURL) }
    }

    /// "+3/10" when 3 of 10 comments are new to the viewer, else "10".
    private var commentsText: String {
        let count = pr.newComments > 0 ? "+\(pr.newComments)/\(pr.comments)" : "\(pr.comments)"
        return element.style == .text ? "\(count) comment\(pr.comments == 1 ? "" : "s")" : count
    }

    @ViewBuilder
    private func styled(icon: some View, text: String) -> some View {
        switch element.style {
        case .iconAndText: HStack(spacing: 3) { icon; Text(text) }
        case .icon: icon.help(text)
        case .text: Text(text)
        }
    }

    @ViewBuilder
    private var ciIcon: some View {
        switch pr.ci {
        case .running:
            Spinner(highlighted: highlighted)
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(highlighted ? .white : .green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(highlighted ? .white : .red)
        case .none:
            Image(systemName: "circle.dashed").foregroundStyle(highlighted ? Color.white : Color.primary.opacity(0.72))
        }
    }

    private var reviewIcon: some View {
        let (name, color): (String, Color) =
            if pr.changesRequested { ("exclamationmark.circle.fill", .orange) }
            else if pr.approvals > 0 { ("checkmark.circle.fill", .green) }
            // a comment is not a decision: shown as not reviewed
            else { ("person.crop.circle.badge.questionmark", Color.primary.opacity(0.72)) }
        return Image(systemName: name).foregroundStyle(highlighted ? .white : color)
    }

    @ViewBuilder
    private var orgIcon: some View {
        let alias = layout.alias(for: pr.org)
        // an emoji or symbol icon without a value falls back to the avatar
        let kind = alias.map { ($0.iconKind == .emoji || $0.iconKind == .symbol) && $0.iconValue.isEmpty ? .avatar : $0.iconKind } ?? .avatar
        switch kind {
        case .avatar:
            AsyncImage(url: URL(string: "https://github.com/\(pr.org).png?size=40")) { image in
                image.resizable()
            } placeholder: {
                Image(systemName: "building.2")
            }
            .frame(width: 12, height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        case .symbol:
            Image(systemName: alias?.iconValue.isEmpty == false ? alias!.iconValue : "folder")
        case .emoji:
            Text(alias?.iconValue ?? "")
        case .none:
            EmptyView()
        }
    }
}

/// Overlapping round avatars with a "+N" circle for the rest.
struct AvatarStack: View {
    let people: [Participant]
    let total: Int
    let highlighted: Bool
    private let size: CGFloat = 18
    private let shown = 4

    var body: some View {
        HStack(spacing: -5) {
            ForEach(Array(people.prefix(shown).enumerated()), id: \.element.login) { index, person in
                avatar(person)
                    .linked(person.profileURL)
                    .zIndex(Double(shown - index))
            }
            if total > min(shown, people.count) {
                circle(Color.gray.gradient) {
                    Text("+\(total - min(shown, people.count))").font(.system(size: 8, weight: .semibold))
                }
            }
        }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
    }

    private func avatar(_ person: Participant) -> some View {
        AsyncImage(url: person.avatarURL) { image in
            image.resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle()).overlay(ring)
        } placeholder: {
            circle(color(for: person.login).gradient) {
                Text(person.login.prefix(1).uppercased()).font(.system(size: 9, weight: .semibold))
            }
        }
    }

    private func circle(_ fill: some ShapeStyle, @ViewBuilder label: () -> some View) -> some View {
        Circle().fill(fill)
            .frame(width: size, height: size)
            .overlay(label().foregroundStyle(.white))
            .overlay(ring)
    }

    private var ring: some View {
        Circle().strokeBorder(highlighted ? Color.accentColor : Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
    }

    /// A stable color per login for the placeholder.
    private func color(for login: String) -> Color {
        let hash = login.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.85)
    }
}

/// A small spinner sized like an inline icon, for CI that is still running.
struct Spinner: View {
    var highlighted = false

    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.mini)
            .tint(highlighted ? .white : .yellow)
            .frame(width: 13, height: 13)
            .help("CI is running")
    }
}

/// A soft yellow pill behind an element that changed since the viewer last looked.
struct ChangedMark: ViewModifier {
    let highlighted: Bool
    let active: Bool

    func body(content: Content) -> some View {
        if active {
            // takes its own room, so the pill never covers the next element
            content
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color.yellow.opacity(highlighted ? 0.45 : 0.3)))
                .help("Changed since you last looked")
        } else {
            content
        }
    }
}

/// The PR's latest commit, in the chosen commit style; a click opens that commit on GitHub.
struct CommitLink: View {
    let pr: PullRequest
    let style: ElementStyle
    let commitStyle: CommitStyle
    let highlighted: Bool
    var now = Date()

    private var ink: Color { highlighted ? .white : Color.primary.opacity(0.72) }
    private var hash: String { String(pr.activity.oid.prefix(7)) }

    var body: some View {
        content
            .foregroundStyle(ink)
            .linked(pr.url.appendingPathComponent("commits").appendingPathComponent(pr.activity.oid))
            .help(pr.commitMessage.isEmpty ? hash : "\(hash) \(pr.commitMessage)")
    }

    @ViewBuilder
    private var content: some View {
        let mono = Text(hash).font(.system(size: 11, design: .monospaced))
        switch commitStyle {
        case .hash:
            HStack(spacing: 3) {
                if style != .text { CommitGlyph() }
                if style != .icon { mono }
            }
        case .hashAndMessage:
            HStack(spacing: 5) {
                mono
                Text(pr.commitMessage).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: 240, alignment: .leading)
        case .full:
            HStack(spacing: 5) {
                CommitGlyph()
                mono
                Text(pr.commitMessage).lineLimit(1).truncationMode(.tail).layoutPriority(-1)
                if !pr.commitAuthor.isEmpty { Text("· \(pr.commitAuthor)").opacity(0.8) }
                if let date = pr.commitDate { Text("· \(relativeAge(date, now: now)) ago").opacity(0.8) }
            }
        case .pill:
            mono
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(highlighted ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)))
        }
    }
}

/// GitHub's commit symbol: a ring on a horizontal line. SF Symbols has no such icon.
struct CommitGlyph: View {
    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            let radius = size.height * 0.27
            let center = CGPoint(x: size.width / 2, y: mid)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: mid))
            line.addLine(to: CGPoint(x: center.x - radius, y: mid))
            line.move(to: CGPoint(x: center.x + radius, y: mid))
            line.addLine(to: CGPoint(x: size.width, y: mid))
            let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: mid - radius, width: radius * 2, height: radius * 2))
            context.stroke(line, with: .foreground, lineWidth: 1.4)
            context.stroke(ring, with: .foreground, lineWidth: 1.4)
        }
        .frame(width: 15, height: 12)
    }
}

/// The PR title; underlined while the pointer is on it, as a hint that a click opens the PR.
struct PRTitle: View {
    let text: String
    let maxLines: Int
    let highlighted: Bool
    @State private var hovered = false

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .underline(hovered)
            .foregroundStyle(highlighted ? Color.white : Color.primary)
            .lineLimit(maxLines)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onHover { hovered = $0 }
    }
}
