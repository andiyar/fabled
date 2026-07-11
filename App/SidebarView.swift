import SwiftUI
import ClaudeKit
import FabledCore

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selection) {
            if !app.searchQuery.isEmpty {
                searchResults
            } else {
                liveSection
                historySections
            }
        }
        .searchable(text: $app.searchQuery, placement: .sidebar, prompt: "Search sessions")
        .overlay(alignment: .bottom) {
            if app.isIndexing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Indexing…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(6)
            }
        }
    }

    @ViewBuilder private var liveSection: some View {
        if !app.liveSessions.isEmpty {
            Section("Live") {
                ForEach(app.liveSessions) { session in
                    HStack(spacing: Theme.spaceS) {
                        SessionStatusBadge(state: session.activityState)
                        VStack(alignment: .leading) {
                            Text(session.title).lineLimit(1)
                                .fontWeight(session.activityState == .needsApproval
                                    ? .semibold : .regular)
                            Text(statusLine(for: session))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .listRowBackground(
                        session.activityState == .needsApproval
                            ? Theme.statusNeedsInput.opacity(0.10) : nil)
                    .tag(AppModel.Selection.live(session.id))
                    .contextMenu {
                        Button("End Session", role: .destructive) {
                            app.close(session)
                        }
                    }
                }
            }
        }
    }

    private var historySections: some View {
        ForEach(app.history) { group in
            Section(group.project.displayName) {
                // v1 keeps sections shallow; search covers the deep tail.
                ForEach(group.sessions.prefix(10)) { summary in
                    VStack(alignment: .leading) {
                        Text(summary.title).lineLimit(1)
                        Text(summary.lastActivity, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(AppModel.Selection.historical(summary.id))
                }
                if group.sessions.count > 10 {
                    Text("\(group.sessions.count - 10) more — use search")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var searchResults: some View {
        Section("Results") {
            ForEach(app.searchHits) { hit in
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.session.title).lineLimit(1)
                    Text(hit.snippet).font(.caption)
                        .foregroundStyle(.secondary).lineLimit(2)
                }
                .tag(AppModel.Selection.historical(hit.session.id))
            }
        }
    }

    /// Second line: what the session is waiting on beats where it lives.
    private func statusLine(for session: ChatSession) -> String {
        if let gate = session.pendingGate { return gate.summaryLine }
        return session.workingDirectory.lastPathComponent
    }
}
