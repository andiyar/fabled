import SwiftUI
import FabledCore

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 560)
        .task { await app.bootstrap() }
    }

    @ViewBuilder private var detail: some View {
        switch app.selection {
        case .live(let id):
            if let session = app.liveSessions.first(where: { $0.id == id }) {
                Text(session.title)   // Task 10 replaces with ConversationView
            } else {
                Text("Session ended")
            }
        case .historical(let id):
            if let summary = app.summary(forSessionID: id) {
                Text(summary.title)   // Task 10 replaces with HistoricalSessionView
            } else {
                Text("Not found")
            }
        case nil:
            Text("Select a session").foregroundStyle(.secondary)
        }
    }
}
