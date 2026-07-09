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
        .alert("Session failed", isPresented: .constant(app.launchError != nil)) {
            Button("OK") { }
        } message: {
            Text(app.launchError ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.selection {
        case .live(let id):
            if let session = app.liveSessions.first(where: { $0.id == id }) {
                ConversationView(session: session)
            } else {
                WelcomeView(newSession: startScratchSession)
            }
        case .historical(let id):
            if let summary = app.summary(forSessionID: id) {
                HistoricalSessionView(summary: summary)
            } else {
                Text("Not found")
            }
        case nil:
            WelcomeView(newSession: startScratchSession)
        }
    }

    /// TEMPORARY (Task 12 replaces with a folder picker): scratch dir session.
    private func startScratchSession() {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("fabled-scratch")
        try? FileManager.default.createDirectory(
            at: scratch, withIntermediateDirectories: true)
        Task { await app.newSession(at: scratch) }
    }
}
