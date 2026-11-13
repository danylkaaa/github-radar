import AppKit
import PRCore
import SwiftUI

/// A popover list header in the menu style.
struct PopoverHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.55))
            .padding(.horizontal, 9)
            .padding(.top, 4)
            .padding(.bottom, 2)
    }
}

/// Who reviewed the PR and how, and who is still asked to.
struct ReviewersList: View {
    let pr: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let reviewers = pr.reviewerList.filter { $0.state != .commented }
            PopoverHeader(text: pr.changesRequested ? "Changes requested" : pr.approvals > 0 ? pr.reviewLabel : "No reviews yet")
            if reviewers.isEmpty {
                Text("Nobody reviewed or was asked to review yet")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.72))
                    .padding(.horizontal, 9).padding(.vertical, 4)
            }
            ForEach(reviewers) { reviewer in
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Avatar(login: reviewer.login, url: reviewer.avatarURL, size: 20)
                        Text(reviewer.login).font(.system(size: 13))
                    }
                    .linked(reviewer.profileURL)
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Image(systemName: icon(reviewer.state)).foregroundStyle(color(reviewer.state))
                        Text(reviewer.state.label).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.72))
                        if let at = reviewer.at {
                            Text("\(relativeAge(at, now: .now)) ago").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55))
                        }
                    }
                    .linked(reviewer.reviewURL)
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
            }
        }
        .padding(5)
        .frame(width: 340)
    }

    // the same icons as the review status on the card
    private func icon(_ state: Reviewer.State) -> String {
        switch state {
        case .approved: "checkmark.circle.fill"
        case .changesRequested: "exclamationmark.circle.fill"
        case .commented: "person.crop.circle"
        case .requested: "person.crop.circle.badge.clock"
        }
    }

    private func color(_ state: Reviewer.State) -> Color {
        switch state {
        case .approved: .green
        case .changesRequested: .orange
        case .commented, .requested: Color.primary.opacity(0.72)
        }
    }
}

/// The PR's comments: the conversation, then review threads with their file and line. New ones are marked.
struct CommentsList: View {
    let pr: PullRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !pr.conversation.isEmpty {
                    PopoverHeader(text: "Conversation")
                    ForEach(pr.conversation.reversed()) { CommentRow(comment: $0) }
                }
                ForEach(pr.threads.reversed()) { thread in
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                        Text(thread.line.map { "\(thread.path):\($0)" } ?? thread.path)
                            .lineLimit(1).truncationMode(.head)
                        if thread.isResolved {
                            Text("Resolved").font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.2)))
                        }
                        if thread.totalCount > thread.comments.count {
                            Text("+\(thread.totalCount - thread.comments.count) earlier").opacity(0.7)
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .linked(thread.comments.first?.url)
                    .padding(.horizontal, 9)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    ForEach(thread.comments) { CommentRow(comment: $0, indented: true) }
                }
                if pr.conversation.isEmpty && pr.threads.isEmpty {
                    Text("No comments").font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.72)).padding(9)
                }
            }
            .padding(5)
        }
        .frame(width: 420)
        .frame(maxHeight: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct CommentRow: View {
    let comment: Comment
    var indented = false
    @State private var hovered = false

    /// The body on one run of text: blank lines and tables would otherwise take height with nothing to show.
    private var preview: String {
        comment.body.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Avatar(login: comment.author, url: comment.avatarURL, size: 20).linked(profileURL(comment.author))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if comment.isNew {
                        Circle().fill(hovered ? Color.white : Color.accentColor).frame(width: 6, height: 6)
                    }
                    Text(comment.author).font(.system(size: 12, weight: .semibold)).linked(profileURL(comment.author))
                    Text("\(relativeAge(comment.createdAt, now: .now)) ago").font(.system(size: 11)).opacity(0.6)
                }
                Text(preview.isEmpty ? "(no text)" : preview)
                    .font(.system(size: 12))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(hovered ? Color.white : Color.primary)
        .padding(.leading, indented ? 21 : 9)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 4).fill(hovered ? Color.accentColor : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 && comment.url != nil }
        .onTapGesture {
            guard let url = comment.url else { return }
            closeDropdown()
            NSWorkspace.shared.open(url)
        }
    }
}

/// A round GitHub avatar; a colored circle with the initial until it loads.
struct Avatar: View {
    let login: String
    let url: URL?
    var size: CGFloat = 18

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Circle().fill(avatarColor(login).gradient)
                .overlay(Text(login.prefix(1).uppercased())
                    .font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A stable color per login.
func avatarColor(_ login: String) -> Color {
    let hash = login.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    return Color(hue: Double(hash % 360) / 360, saturation: 0.45, brightness: 0.85)
}

/// Everyone on the PR and what each did: authored, approved, asked for changes, commented, or is asked to review.
struct PeopleList: View {
    let pr: PullRequest

    private struct Person: Identifiable {
        let login: String
        let avatarURL: URL?
        var profileURL: URL? = nil
        var id: String { login }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(text: "Participants (\(pr.participantCount))")
            ForEach(people) { person in
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Avatar(login: person.login, url: person.avatarURL, size: 20)
                        Text(person.login).font(.system(size: 13))
                    }
                    .linked(person.profileURL)
                    if person.login == pr.viewer {
                        Text("you").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
                    }
                    Spacer(minLength: 12)
                    actions(of: person.login)
                }
                .padding(.horizontal, 9)
                .frame(height: 26)
            }
            if pr.participantCount > people.count {
                Text("\(pr.participantCount - people.count) more")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55))
                    .padding(.horizontal, 9).padding(.vertical, 3)
            }
        }
        .padding(5)
        .frame(width: 320)
    }

    /// Participants first, then reviewers GitHub does not list as participants yet (e.g. a requested team).
    private var people: [Person] {
        var list = pr.participants.map { Person(login: $0.login, avatarURL: $0.avatarURL, profileURL: $0.profileURL) }
        for reviewer in pr.reviewerList where !list.contains(where: { $0.login == reviewer.login }) {
            list.append(Person(login: reviewer.login, avatarURL: reviewer.avatarURL, profileURL: reviewer.profileURL))
        }
        return list
    }

    @ViewBuilder
    private func actions(of login: String) -> some View {
        let state = pr.reviewerList.first { $0.login == login }?.state
        let comments = pr.conversation.filter { $0.author == login }.count
            + pr.threads.flatMap(\.comments).filter { $0.author == login }.count
        HStack(spacing: 8) {
            if login == pr.author {
                Image(systemName: "pencil.circle.fill").foregroundStyle(Color.primary.opacity(0.72)).help("Author")
            }
            let reviewURL = pr.reviewerList.first { $0.login == login }?.reviewURL
            switch state {
            case .approved?:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).linked(reviewURL)
            case .changesRequested?:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).linked(reviewURL)
            case .requested?:
                Image(systemName: "clock").foregroundStyle(Color.primary.opacity(0.72)).help("Review requested")
            default:
                EmptyView()
            }
            if comments > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "bubble.left")
                    Text("\(comments)").monospacedDigit()
                }
                .foregroundStyle(Color.primary.opacity(0.72))
                .help("\(comments) comment\(comments == 1 ? "" : "s") (of the latest ones the app loads)")
            }
        }
        .font(.system(size: 13))
    }
}

/// The PR's latest commits and its size; each commit is a link to itself in the PR.
struct CommitsList: View {
    let pr: PullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                PopoverHeader(text: "\(pr.activity.commits) commit\(pr.activity.commits == 1 ? "" : "s")")
                Spacer()
                HStack(spacing: 6) {
                    Text("\(pr.changedFiles) file\(pr.changedFiles == 1 ? "" : "s")").foregroundStyle(Color.primary.opacity(0.6))
                    Text(verbatim: "+\(pr.additions)").foregroundStyle(.green)
                    Text(verbatim: "−\(pr.deletions)").foregroundStyle(.red)
                }
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .linked(pr.url.appendingPathComponent("files"))
                .padding(.trailing, 9)
            }
            ForEach(pr.recentCommits) { commit in
                HStack(spacing: 8) {
                    Text(String(commit.oid.prefix(7))).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color.primary.opacity(0.6))
                    Text(commit.message).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(commit.author).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.6))
                        .linked(profileURL(commit.author))
                    if let date = commit.date {
                        Text(relativeAge(date, now: .now)).font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55))
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .linked(pr.url.appendingPathComponent("commits").appendingPathComponent(commit.oid))
            }
            if pr.activity.commits > pr.recentCommits.count {
                Text("\(pr.activity.commits - pr.recentCommits.count) earlier")
                    .font(.system(size: 12)).foregroundStyle(Color.primary.opacity(0.55))
                    .padding(.horizontal, 9).padding(.vertical, 3)
            }
        }
        .padding(5)
        .frame(width: 440)
    }
}
