import SwiftUI
import ClaudeKit
import FabledCore

/// The attention inbox (feature 13, CD digest §1): what needs Ben, what's
/// working, what's recent — composer-first once T10 lands. Shown on launch,
/// on ⌘N, and whenever nothing is selected.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    let newSession: () -> Void

    private var needsInput: [ChatSession] {
        app.liveSessions.filter { $0.activityState == .needsApproval }
    }
    private var working: [ChatSession] {
        app.liveSessions.filter { $0.activityState == .working }
    }
    private var idleLive: [ChatSession] {
        app.liveSessions.filter {
            $0.activityState == .idle || $0.activityState == .ended
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceXL) {
                header
                if !needsInput.isEmpty {
                    inboxSection("Needs your input", sessions: needsInput)
                }
                if !working.isEmpty {
                    inboxSection("Working", sessions: working)
                }
                if !idleLive.isEmpty {
                    inboxSection("Open sessions", sessions: idleLive)
                }
                recentsSection
                // T10 composer slot
            }
            .padding(Theme.spaceXL)
            .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.welcomeBackdrop)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Text("Fabled")
                .font(Theme.display)
                .foregroundStyle(Theme.bronze)
            Text("Native Claude Code for the Mac")
                .font(Theme.assistantFont(.callout))
                .foregroundStyle(.secondary)
        }
        .padding(.top, Theme.spaceXL)
    }

    private func inboxSection(_ title: String, sessions: [ChatSession]) -> some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            Text(title).font(Theme.heading)
            ForEach(sessions) { session in
                WelcomeLiveRow(session: session) {
                    app.selection = .live(session.id)
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            HStack {
                Text("Recent").font(Theme.heading)
                Spacer()
                Button("Open folder…", action: newSession)
                    .controlSize(.small)
            }
            let recents = app.welcomeRecents(limit: 8)
            if recents.isEmpty {
                Text("No sessions yet — open a folder to begin.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(recents) { summary in
                WelcomeRecentRow(summary: summary) {
                    app.selection = .historical(summary.id)
                }
            }
        }
    }
}

/// One live-session inbox row: status chip with WORDS, title, and — for
/// needs-input — a preview of what the agent is waiting on (digest §1).
private struct WelcomeLiveRow: View {
    let session: ChatSession
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.spaceM) {
            SessionStatusBadge(state: session.activityState, labeled: true)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).lineLimit(1)
                Text(previewLine)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(session.workingDirectory.lastPathComponent)
                .font(.caption).foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(Theme.spaceM)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var previewLine: String {
        if let gate = session.pendingGate { return gate.summaryLine }
        if session.isWorking { return "Working…" }
        return "Ready"
    }
}

private struct WelcomeRecentRow: View {
    let summary: SessionSummary
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.spaceM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title).lineLimit(1)
                Text(summary.project.displayName)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(summary.lastActivity, format: .relative(presentation: .named))
                .font(.caption).foregroundStyle(.tertiary)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(Theme.spaceM)
        .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
