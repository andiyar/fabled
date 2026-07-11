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

    private var levels: [String] {
        guard let current = session.currentModel,
              let match = session.models.first(where: {
                  $0.value == current || $0.resolvedModel == current
              }),
              match.supportsEffort
        else { return Self.fallbackLevels }
        return match.supportedEffortLevels.isEmpty
            ? Self.fallbackLevels : match.supportedEffortLevels
    }

    var body: some View {
        Menu {
            Section("This session") {
                ForEach(levels, id: \.self) { level in
                    optionButton(level, title: level.capitalized)
                }
                optionButton("auto", title: "Auto")
            }
            .disabled(session.pendingGate != nil || session.hasEnded)
            Section("New sessions") {
                defaultButton(nil, title: "CLI default")
                ForEach(Self.fallbackLevels, id: \.self) { level in
                    defaultButton(level, title: level.capitalized)
                }
            }
        } label: {
            Label(session.currentEffort?.capitalized ?? "Effort",
                  systemImage: "gauge.with.needle")
                .labelStyle(.titleAndIcon)
        }
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
