import SwiftUI
import ClaudeKit
import FabledCore

struct SidebarView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        List(selection: $app.selection) {
            homeRow
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
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Group by", selection: $app.sidebarOptions.groupBy) {
                        Text("Project").tag(SidebarOptions.GroupBy.project)
                        Text("Date").tag(SidebarOptions.GroupBy.date)
                        Text("None").tag(SidebarOptions.GroupBy.none)
                    }
                    Picker("Sort by", selection: $app.sidebarOptions.sortBy) {
                        Text("Recency").tag(SidebarOptions.SortBy.recency)
                        Text("Name").tag(SidebarOptions.SortBy.name)
                    }
                    Picker("Last activity", selection: Binding(
                        get: { app.sidebarOptions.activityWindow.days ?? 0 },
                        set: { app.sidebarOptions.activityWindow = $0 == 0 ? .all : .days($0) }
                    )) {
                        ForEach(SidebarOptions.ActivityWindow.presets, id: \.label) { preset in
                            Text(preset.label).tag(preset.days ?? 0)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Group, sort, and filter sessions")
            }
        }
    }

    /// Always-visible way back to the welcome inbox (UX-LEDGER row 23: no
    /// return-to-welcome). `Selection` has no case for it, so it can't
    /// `.tag()` into the List's selection binding like a session row does —
    /// a plain button sidesteps that binding entirely while still sitting
    /// in the row flow, top of list, above Live.
    private var homeRow: some View {
        Button {
            app.goHome()
        } label: {
            HStack(spacing: Theme.spaceS) {
                Image(systemName: "house")
                    .foregroundStyle(Theme.accentBronze)
                Text("Home")
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        ForEach(app.sidebarSections) { section in
            Section(section.title) {
                // v1 keeps sections shallow; search covers the deep tail.
                ForEach(section.sessions.prefix(10)) { summary in
                    VStack(alignment: .leading) {
                        Text(summary.title).lineLimit(1)
                        Text(summary.lastActivity, format: .relative(presentation: .named))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(AppModel.Selection.historical(summary.id))
                    .contextMenu {
                        Button(app.sidebarOptions.pinnedSessionIDs.contains(summary.id)
                            ? "Unpin" : "Pin") { app.togglePin(summary.id) }
                        Button("Continue Session") {
                            Task { await app.resume(summary, fork: false) }
                        }
                        Button("Fork Session") {
                            Task { await app.resume(summary, fork: true) }
                        }
                    }
                }
                if section.sessions.count > 10 {
                    Text("\(section.sessions.count - 10) more — use search")
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
