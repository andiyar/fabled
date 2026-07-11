import SwiftUI
import ClaudeKit
import FabledCore

struct HistoricalSessionView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    @State private var items: [TimelineItem]?
    @State private var inspectedID: String?
    @State private var isInspectorPresented = false
    @State private var expandedGroups: Set<String> = []

    private var inspectedItem: TimelineItem? {
        guard let inspectedID else { return nil }
        return (items ?? []).first(where: { $0.id == inspectedID })
    }

    /// One action for the transcript rows and the inspector's sub-rows.
    /// Injected directly onto the concrete rows ScrollView (main timeline) and
    /// handed explicitly to InspectorPanel (drill-down) — never relied on via
    /// inheritance across the `.inspector` presentation boundary.
    /// `id` gives the action a stable Equatable identity so the environment
    /// value does not churn per render (see InspectItemAction / the row-click
    /// note in TimelineItemViews.swift for WHY that matters).
    private var inspectAction: InspectItemAction {
        InspectItemAction(id: "historical-\(summary.id)") { id in
            inspectedID = id
            isInspectorPresented = true
        }
    }

    var body: some View {
        // Presentation/structural modifiers (.inspector, .toolbar,
        // .navigationTitle, .task) attach to this always-present concrete
        // VStack, mirroring ConversationView's proven-working shape, rather than
        // to a `Group` whose conditional child identity swaps (ProgressView →
        // ScrollView) once `.task` loads. Attaching a presentation modifier to a
        // stable concrete root — not a Group over a swapping branch — is the
        // boring, reliable shape; the loading/loaded conditional nests INSIDE.
        VStack(spacing: 0) {
            if let items {
                // Match ConversationView: short transcripts lay out from the top
                // (minHeight fills the viewport), long ones follow the bottom.
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(TimelineDisplay.grouped(items)) { row in
                                switch row {
                                case .item(let item):
                                    TimelineItemView(item: item, session: nil)
                                case .toolGroup(let id, let groupItems, let summary):
                                    ToolGroupRow(
                                        id: id, items: groupItems, summary: summary,
                                        isExpanded: expandedGroups.contains(id),
                                        toggle: {
                                            if expandedGroups.contains(id) {
                                                expandedGroups.remove(id)
                                            } else {
                                                expandedGroups.insert(id)
                                            }
                                        })
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .defaultScrollAnchor(.bottom)
                }
            } else {
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(summary.title)
        .navigationSubtitle(summary.project.displayName)
        // Top-level chain, above .inspector — mirrors ConversationView, the
        // empirically working configuration (see 2026-07-09 note there).
        .environment(\.inspectItem, inspectAction)
        .inspector(isPresented: $isInspectorPresented) {
            // Threaded in explicitly — presented inspector content does not
            // inherit the transcript's `.environment(\.inspectItem)`.
            InspectorPanel(item: inspectedItem,
                           subagentItems: nil,
                           inspectItem: inspectAction,
                           inspectedID: $inspectedID)
                .inspectorColumnWidth(min: 300, ideal: 420, max: 640)
        }
        .toolbar {
            ToolbarItemGroup {
                // Independent presentation-path affordance (matches
                // ConversationView) — verifiable without clicking a row.
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle inspector")
                .keyboardShortcut("i", modifiers: [.command, .option])
                Button("Continue") { Task { await app.resume(summary, fork: false) } }
                    .buttonStyle(.borderedProminent).tint(Theme.clay)
                    .help("Reattach a live session to this same session id")
                Button("Fork") { Task { await app.resume(summary, fork: true) } }
                    .help("Branch a NEW session seeded with this history")
            }
        }
        .task(id: summary.id) {
            let requested = summary.id
            items = nil
            expandedGroups.removeAll()
            let loaded = await app.historicalTimeline(for: summary)
            // Rapid switching: a slow load must not land on a newer selection
            // (FOLLOWUPS stale-assignment window).
            guard !Task.isCancelled, requested == summary.id else { return }
            items = loaded
        }
    }
}
