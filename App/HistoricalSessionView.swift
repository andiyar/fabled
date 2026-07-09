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
    /// Injected DIRECTLY onto the concrete ScrollView (below) rather than on the
    /// root: this view's root is a `Group` whose real content lives behind an
    /// `if let items` branch, and a custom `.environment` applied above that
    /// branch boundary (alongside `.inspector`/`.toolbar`/`.task` in a
    /// NavigationSplitView detail column) was not being re-delivered to the
    /// loaded branch when it materialized — so the rows read a nil action and
    /// clicks no-op'd, even though the Button (and its `.help` tooltip) rendered
    /// fine. The live ConversationView never hit this because its root is an
    /// always-present concrete `VStack` (no branch flip). Applying the action on
    /// the concrete rows container removes the branch/presentation subtlety.
    private var inspectAction: InspectItemAction {
        InspectItemAction { id in
            inspectedID = id
            isInspectorPresented = true
        }
    }

    var body: some View {
        Group {
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
                    // See `inspectAction`: injected on the concrete rows
                    // container, below the `if let` branch boundary.
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
