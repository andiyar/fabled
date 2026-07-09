import SwiftUI
import ClaudeKit
import FabledCore

struct HistoricalSessionView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    @State private var items: [TimelineItem]?

    var body: some View {
        Group {
            if let items {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(items) { item in
                            TimelineItemView(item: item, session: nil)
                        }
                    }
                    .padding()
                }
                .defaultScrollAnchor(.bottom)
            } else {
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(summary.title)
        .navigationSubtitle(summary.project.displayName)
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
