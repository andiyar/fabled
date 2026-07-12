import SwiftUI
import FabledCore

/// Catalog-driven effort picker (probe finding 5). Session-scoped changes
/// ride the CLI's own /effort command; "Auto" is the CLI's adaptive mode
/// (catalog argumentHint includes it even though supportedEffortLevels
/// doesn't). The "New sessions" section sets the persisted spawn default
/// (--effort, what Claude Desktop passes). Session controls are disabled
/// while a gate is pending — a slash send would queue behind the CLI's
/// open question.
struct EffortPickerMenu: View {
    @Environment(AppModel.self) private var app
    let session: ChatSession
    static let fallbackLevels = ["low", "medium", "high", "xhigh", "max"]

    /// nil = the current model matched a catalog entry that declares
    /// supportsEffort == false — effort is genuinely unavailable, not merely
    /// unknown. Unknown (no catalog match) falls back to the standard five.
    private var levels: [String]? {
        guard let current = session.currentModel,
              let match = session.models.first(where: {
                  $0.value == current || $0.resolvedModel == current
              })
        else { return Self.fallbackLevels }
        guard match.supportsEffort else { return nil }
        return match.supportedEffortLevels.isEmpty
            ? Self.fallbackLevels : match.supportedEffortLevels
    }

    var body: some View {
        Menu {
            Section("This session") {
                if let levels {
                    ForEach(levels, id: \.self) { level in
                        optionButton(level, title: level.capitalized)
                    }
                    if !levels.contains("auto") {
                        optionButton("auto", title: "Auto")
                    }
                } else {
                    Text("Not supported by this model")
                }
            }
            .disabled(session.pendingGate != nil || session.hasEnded)
            Section("New sessions") {
                defaultButton(nil, title: "CLI default")
                ForEach(Self.fallbackLevels, id: \.self) { level in
                    defaultButton(level, title: level.capitalized)
                }
            }
        } label: {
            ChipLabel(icon: "gauge.with.needle",
                      label: session.currentEffort?.capitalized ?? "Effort",
                      textColor: Theme.ink)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Model effort — lower is faster")
    }

    @ViewBuilder
    private func optionButton(_ level: String, title: String) -> some View {
        Button { session.setEffort(level) } label: {
            if session.currentEffort == level {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private func defaultButton(_ level: String?, title: String) -> some View {
        Button { app.preferredEffort = level } label: {
            if app.preferredEffort == level {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
