import SwiftUI
import ClaudeKit
import FabledCore

struct HistoricalSessionView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    @State private var items: [TimelineItem]?
    @State private var inspectedID: String?
    @State private var isInspectorPresented = false

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
                        .frame(maxWidth: 760, alignment: .leading)
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
        .environment(\.inspectItem, InspectItemAction { id in
            inspectedID = id
            isInspectorPresented = true
        })
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(items: items ?? [],
                           subagentTimelines: [:],
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
