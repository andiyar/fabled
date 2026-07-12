import SwiftUI
import ClaudeKit
import FabledCore

/// The attention inbox (feature 13, CD digest §1): what's waiting on Ben,
/// what's working, and what he touched lately — in plain English on the
/// locked palette. Shown on launch, on ⌘N, and whenever nothing is selected.
struct WelcomeView: View {
    @Environment(AppModel.self) private var app
    let newSession: () -> Void

    @State private var draft = ""
    @State private var chosenProject: ProjectFolder?
    @FocusState private var composerFocused: Bool

    private var targetProject: ProjectFolder? {
        chosenProject ?? app.recentProjects(limit: 1).first
    }

    // "Waiting on you" = needs-your-reply first, then ready-to-review.
    private var needsReply: [ChatSession] {
        app.liveSessions.filter { $0.activityState == .needsApproval }
    }
    private var readyToReview: [ChatSession] {
        app.liveSessions.filter { $0.activityState == .idle }
    }
    private var waitingOnYou: [ChatSession] { needsReply + readyToReview }
    private var working: [ChatSession] {
        app.liveSessions.filter { $0.activityState == .working }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceXL) {
                header
                if !waitingOnYou.isEmpty { waitingSection }
                if !working.isEmpty { workingSection }
                latelySection
                composer
            }
            .padding(Theme.spaceXL)
            .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.spaceXS) {
            Text("Welcome back, Ben")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
            Text("Fabled")
                .font(Theme.wordmark)
                .foregroundStyle(Theme.wordmarkColor)
            Text("Native Claude Code for the Mac")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, Theme.spaceS)
    }

    // MARK: - Waiting on you (row 24: only shown when something is waiting)

    private var waitingSection: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            sectionTitle("Waiting on you")
            ForEach(waitingOnYou) { session in
                WelcomeAttentionRow(session: session) {
                    app.selection = .live(session.id)
                }
            }
        }
    }

    // MARK: - Working

    private var workingSection: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            sectionTitle("Working")
            ForEach(working) { session in
                WelcomeWorkingRow(session: session) {
                    app.selection = .live(session.id)
                }
            }
        }
    }

    // MARK: - Lately

    private var latelySection: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            sectionTitle("Lately")
            let recents = app.welcomeRecents(limit: 8)
            if recents.isEmpty {
                Text("No sessions yet — open a folder to begin.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            }
            ForEach(Array(recents.enumerated()), id: \.element.id) { index, summary in
                WelcomeLatelyRow(summary: summary) {
                    app.selection = .historical(summary.id)
                }
                if index < recents.count - 1 {
                    Rectangle().fill(Theme.hairline).frame(height: 1)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.heading)
            .foregroundStyle(Theme.ink)
    }

    // MARK: - Composer (B1.4 extends the chip row with model / effort / Auto)

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.spaceM) {
            TextField("Message Claude to begin…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...4)
                .focused($composerFocused)
                .onSubmit(startSession)
            HStack(spacing: Theme.spaceS) {
                projectChip
                ComposerChips(target: .newSession)
                Spacer(minLength: Theme.spaceS)
                sendButton
            }
        }
        .padding(Theme.spaceM)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        // Type-to-start: land focus in the composer so the welcome screen is
        // usable from the keyboard on appear.
        .onAppear { composerFocused = true }
    }

    private var projectChip: some View {
        Menu {
            ForEach(app.recentProjects(limit: 12)) { project in
                Button {
                    chosenProject = project
                } label: {
                    if project.id == targetProject?.id {
                        Label(project.displayName, systemImage: "checkmark")
                    } else {
                        Text(project.displayName)
                    }
                }
                .help(project.originalPath)
            }
            Divider()
            Button("Open folder…", action: newSession)
        } label: {
            HStack(spacing: Theme.spaceXS) {
                Image(systemName: "folder")
                    .foregroundStyle(Theme.accentBronze)
                Text(targetProject?.displayName ?? "Choose project")
                    .foregroundStyle(Theme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.faint)
            }
            .font(.system(size: 12))
            .padding(.horizontal, Theme.spaceS)
            .padding(.vertical, Theme.spaceXS + 1)
            .background(Theme.panelRecessed, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sendButton: some View {
        Button(action: startSession) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ground)
                .frame(width: 30, height: 30)
                .background(Theme.clay, in: RoundedRectangle(cornerRadius: 8))
                .opacity(canStart ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canStart)
    }

    private var canStart: Bool {
        targetProject != nil
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startSession() {
        guard canStart, let project = targetProject,
              project.originalPath.hasPrefix("/") else { return }
        let directory = URL(fileURLWithPath: project.originalPath)
        let message = draft
        draft = ""
        Task { await app.newSession(at: directory, firstMessage: message) }
    }
}

// MARK: - Rows

/// One "Waiting on you" card: a 2px left accent stripe (amber = needs your
/// reply, slate = ready to review) on a faintly tinted panel, with the
/// labeled status badge, a project · title line, a preview, and a time.
private struct WelcomeAttentionRow: View {
    let session: ChatSession
    let open: () -> Void

    private var accent: Color {
        session.activityState == .needsApproval ? Theme.needsYou : Theme.review
    }
    // Flat left edge (so the 2px stripe reads crisp), rounded right (radius 10).
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 0,
            bottomTrailingRadius: 10, topTrailingRadius: 10)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spaceM) {
            SessionStatusBadge(state: session.activityState, labeled: true)
                .frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: Theme.spaceXS) {
                Text("\(session.workingDirectory.lastPathComponent) · \(session.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(previewLine)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: Theme.spaceS)
            Text(welcomeRelativeStamp(session.lastEventAt))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background {
            ZStack {
                shape.fill(Theme.panel)
                shape.fill(accent.opacity(0.08))
            }
        }
        // Hairline on top/right/bottom; the 2px accent stripe (drawn after)
        // covers the left hairline, so the left edge reads as pure accent.
        .overlay { shape.strokeBorder(Theme.hairline, lineWidth: 1) }
        .overlay(alignment: .leading) { accent.frame(width: 2) }
        .clipShape(shape)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var previewLine: String {
        session.pendingGate?.summaryLine ?? (session.isWorking ? "Working…" : "Ready")
    }
}

/// One "Working" row: a pulsing live dot, a project · title line, and a
/// "Running…" subtitle on a quiet panel.
private struct WelcomeWorkingRow: View {
    let session: ChatSession
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.spaceM) {
            PulsingDot(color: Theme.live)
            VStack(alignment: .leading, spacing: Theme.spaceXS) {
                Text("\(session.workingDirectory.lastPathComponent) · \(session.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("Running…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.spaceS)
            Text(welcomeRelativeStamp(session.lastEventAt))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// One "Lately" row: a quiet title · project with a compact time; tap reopens.
private struct WelcomeLatelyRow: View {
    let summary: SessionSummary
    let open: () -> Void

    var body: some View {
        HStack(spacing: Theme.spaceS) {
            Text(summary.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Text("· \(summary.project.displayName)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer(minLength: Theme.spaceS)
            Text(welcomeRelativeStamp(summary.lastActivity))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.faint)
        }
        .padding(.vertical, Theme.spaceS)
        .padding(.horizontal, Theme.spaceXS)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// A gently pulsing status dot (feature 14 motion): 1.4s ease-in-out,
/// opacity 1↔.35 and scale 1↔.82.
private struct PulsingDot: View {
    let color: Color
    @State private var animating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .opacity(animating ? 0.35 : 1)
            .scaleEffect(animating ? 0.82 : 1)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                       value: animating)
            .onAppear { animating = true }
            .accessibilityHidden(true)
    }
}

/// Compact, mockup-style relative stamp: "now" / "4m" / "1h" / "3d".
private func welcomeRelativeStamp(_ date: Date?) -> String {
    guard let date else { return "now" }
    let seconds = max(0, Date().timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3_600: return "\(Int(seconds / 60))m"
    case ..<86_400: return "\(Int(seconds / 3_600))h"
    default: return "\(Int(seconds / 86_400))d"
    }
}
