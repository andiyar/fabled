import SwiftUI
import FabledCore
import AppKit

struct RootView: View {
    @Environment(AppModel.self) private var app
    /// Inspector-open state hoisted out of ConversationView so it survives
    /// the per-session hierarchy recreation below (the deliberate T6 behavior:
    /// an open inspector stays open across live-session switches).
    @State private var isInspectorPresented = false

    private var pendingApprovals: Int {
        app.liveSessions.reduce(0) { $0 + $1.pendingGates.count }
    }

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(Theme.ground)
        .onChange(of: pendingApprovals) { _, count in
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
        .task { await app.bootstrap() }
        .alert("Session failed", isPresented: Binding(
            get: { app.launchError != nil },
            set: { if !$0 { app.clearLaunchError() } }
        )) {
            Button("OK") { }
        } message: {
            Text(app.launchError ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch app.selection {
        case .live(let id):
            if let session = app.liveSessions.first(where: { $0.id == id }) {
                ConversationView(session: session,
                                 isInspectorPresented: $isInspectorPresented)
                    // Fresh hierarchy per session: kills every cross-session
                    // @State leak in one move (4a T10 rider). Presentation
                    // state that SHOULD survive switches lives up here.
                    .id(session.id)
            } else {
                WelcomeView()
            }
        case .historical(let id):
            if let summary = app.summary(forSessionID: id) {
                HistoricalSessionView(summary: summary)
            } else {
                Text("Not found")
            }
        case nil:
            WelcomeView()
        }
    }
}
