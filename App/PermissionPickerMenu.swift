import SwiftUI
import FabledCore

/// Permission-mode control. The "New sessions" section sets the persisted spawn
/// default (--permission-mode) — the fix for UX-LEDGER row 14, where no code
/// path passed the mode at launch so choosing a mode did nothing. "Auto" is
/// Claude Desktop's adaptive mode (wire string `auto`, seen in its transcripts).
///
/// The "This session" section keeps the existing runtime control (a wire
/// set_permission_mode op); it is disabled while a gate is pending, mirroring
/// EffortPickerMenu — a mid-question mode change would race the CLI.
struct PermissionPickerMenu: View {
    @Environment(AppModel.self) private var app
    let session: ChatSession

    /// Curated modes: wire value → friendly label.
    static let modes: [(mode: String, title: String)] = [
        ("default", "Default"),
        ("plan", "Plan"),
        ("acceptEdits", "Accept Edits"),
        ("bypassPermissions", "Bypass Permissions"),
        ("auto", "Auto"),
    ]

    var body: some View {
        Menu {
            Section("This session") {
                ForEach(Self.modes, id: \.mode) { entry in
                    sessionButton(entry)
                }
            }
            .disabled(session.pendingGate != nil || session.hasEnded)
            Section("New sessions") {
                defaultButton(nil, title: "CLI default")
                ForEach(Self.modes, id: \.mode) { entry in
                    defaultButton(entry.mode, title: entry.title)
                }
            }
        } label: {
            ChipLabel(icon: "lock.shield", label: currentTitle, textColor: Theme.ink)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Permission mode — the New sessions choice is applied at launch")
    }

    private var currentTitle: String {
        Self.modes.first { $0.mode == session.permissionMode }?.title ?? "Permissions"
    }

    @ViewBuilder
    private func sessionButton(_ entry: (mode: String, title: String)) -> some View {
        Button { session.setPermissionMode(entry.mode) } label: {
            if session.permissionMode == entry.mode {
                Label(entry.title, systemImage: "checkmark")
            } else {
                Text(entry.title)
            }
        }
    }

    @ViewBuilder
    private func defaultButton(_ mode: String?, title: String) -> some View {
        Button { app.preferredPermissionMode = mode } label: {
            if app.preferredPermissionMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
