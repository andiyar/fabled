import SwiftUI
import ClaudeKit
import FabledCore

/// Inline approval card (spec: never app-modal — other sessions stay usable).
struct PermissionCardView: View {
    let request: PermissionRequest
    let respond: (PermissionDecision) -> Void
    @State private var denyMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Theme.clay)
                Text(request.displayName ?? request.toolName).fontWeight(.semibold)
                Spacer()
            }
            Text(PermissionPrompt.commandSummary(for: request))
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5),
                            in: RoundedRectangle(cornerRadius: 6))
            if let reason = request.decisionReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            }
            TextField("Reason (optional, sent with Deny)", text: $denyMessage)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            HStack {
                Button("Allow") { respond(.allowAsRequested) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.clay)
                    .keyboardShortcut(.return, modifiers: .command)
                if let label = PermissionPrompt.alwaysAllowLabel(for: request.suggestions) {
                    // Persists via the CLI: suggestions echoed back verbatim
                    // land in the suggestion's destination settings file.
                    Button(label) {
                        respond(.allow(updatedInput: nil,
                                       updatedPermissions: request.suggestions))
                    }
                }
                Spacer()
                Button("Deny") {
                    respond(.deny(message: denyMessage.isEmpty ? nil : denyMessage))
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.clay.opacity(0.5)))
    }
}
