import SwiftUI
import FabledCore

struct ComposerView: View {
    let session: ChatSession
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let permission = session.pendingPermission {
                PermissionCardView(request: permission) { decision in
                    session.respond(to: permission, decision: decision)
                }
                .id(permission.requestID)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Claude…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .onSubmit(send)   // Return sends; ⌥Return inserts a newline
                if session.isWorking {
                    Button(action: session.interrupt) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Interrupt (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Theme.clay : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                // ⌘⏎ belongs to the permission card while one is pending.
                .keyboardShortcut(session.pendingPermission == nil
                    ? KeyboardShortcut(.return, modifiers: .command) : nil)
            }
        }
        .padding(10)
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.hasEnded
    }

    private func send() {
        guard canSend else { return }
        session.send(draft)
        draft = ""
    }
}
