import SwiftUI
import FabledCore
import AppKit

struct RootView: View {
    @Environment(AppModel.self) private var app

    private var pendingApprovals: Int {
        app.liveSessions.reduce(0) { $0 + $1.pendingGates.count }
    }

    var body: some View {
        @Bindable var app = app
        return NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            detail
        }
        .frame(minWidth: 900, minHeight: 560)
        .onChange(of: pendingApprovals) { _, count in
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
        .task { await app.bootstrap() }
        .fileImporter(isPresented: $app.isPickingFolder,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await app.newSession(at: url) }
            }
        }
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
                ConversationView(session: session)
            } else {
                WelcomeView { app.isPickingFolder = true }
            }
        case .historical(let id):
            if let summary = app.summary(forSessionID: id) {
                HistoricalSessionView(summary: summary)
            } else {
                Text("Not found")
            }
        case nil:
            WelcomeView { app.isPickingFolder = true }
        }
    }
}
