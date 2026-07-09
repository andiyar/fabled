import SwiftUI
import ClaudeKit
import FabledCore

struct HistoricalSessionView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    @State private var items: [TimelineItem]?
    @State private var inspectedID: String?
    @State private var isInspectorPresented = false

    private var inspectedItem: TimelineItem? {
        guard let inspectedID else { return nil }
        return (items ?? []).first(where: { $0.id == inspectedID })
    }

    /// One action for the transcript rows and the inspector's sub-rows.
    /// Injected directly onto the concrete rows ScrollView (main timeline) and
    /// handed explicitly to InspectorPanel (drill-down) — never relied on via
    /// inheritance across the `.inspector` presentation boundary.
    private var inspectAction: InspectItemAction {
        InspectItemAction { id in
            inspectedID = id
            isInspectorPresented = true
        }
    }

    var body: some View {
        // The presentation/structural modifiers below (.inspector, .toolbar,
        // .navigationTitle, .task) MUST attach to this always-present concrete
        // VStack — the exact shape ConversationView uses, which is the only
        // configuration we have observed the inspector actually present in.
        //
        // WHY this matters: this view previously rooted on `Group { if let items
        // { rows } else { ProgressView } }` with the modifiers on the Group. A
        // Group forwards its modifiers to its child, and here the child is a
        // conditional whose identity SWAPS (ProgressView → ScrollView) when
        // `.task` finishes loading. `.inspector(isPresented:)` bound to that
        // swapping conditional never established a presentation host, so row
        // clicks set `isInspectorPresented = true` but no panel ever appeared
        // (and the ⌥⌘I toggle, added below, would have failed the same way).
        // Hosting the modifiers on a stable concrete root, with the loading/
        // loaded conditional nested INSIDE, removes that swap from the
        // presentation path entirely.
        VStack(spacing: 0) {
            if let items {
                // Match ConversationView: short transcripts lay out from the top
                // (minHeight fills the viewport), long ones follow the bottom.
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(items) { item in
                                TimelineItemView(item: item, session: nil)
                            }
                        }
                        .padding()
                        .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .defaultScrollAnchor(.bottom)
                    // Injected on the concrete rows container so
                    // ToolCallCard/RawEventView always resolve the action.
                    .environment(\.inspectItem, inspectAction)
                }
            } else {
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(summary.title)
        .navigationSubtitle(summary.project.displayName)
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
                Button("Resume") { Task { await app.resume(summary, fork: false) } }
                Button("Fork") { Task { await app.resume(summary, fork: true) } }
            }
        }
        .task(id: summary.id) {
            items = nil
            items = await app.historicalTimeline(for: summary)
        }
    }
}
