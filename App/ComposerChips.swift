import SwiftUI
import FabledCore

/// The start-composer's sticky spawn-default chips (UX-LEDGER row 22): model,
/// effort, and permission-mode. Each writes the persisted `app.preferred*`
/// field that `AppModel.newSession` reads when it spawns `claude`, so picking
/// a value here drives the next new session's launch — no session exists yet.
///
/// A live-session variant (chips that drive a running `ChatSession` via
/// setModel/setEffort/setPermissionMode) will be added when the conversation
/// composer adopts chips (B2.2); it lives with the real pickers today.
struct ComposerChips: View {
    @Environment(AppModel.self) private var app

    /// No live catalog exists pre-spawn, so offer the hardcoded known-models
    /// list (what `merged(catalog: [])` would return anyway).
    private var newSessionModels: [ModelOption] { ModelOption.knownModels }

    var body: some View {
        HStack(spacing: Theme.spaceS) {
            modelChip
            effortChip
            permissionChip
        }
    }

    // MARK: - Model

    private var modelChip: some View {
        chip(icon: "cpu", label: modelLabel, textColor: Theme.accentBronze) {
            optionButton("Default", isSelected: app.preferredModel == nil) {
                app.preferredModel = nil
            }
            ForEach(newSessionModels) { option in
                optionButton(option.displayName,
                             isSelected: app.preferredModel == option.value) {
                    app.preferredModel = option.value
                }
            }
        }
        .help("Model")
    }

    private var modelLabel: String {
        guard let preferred = app.preferredModel else { return "Default" }
        // A persisted-but-unknown id (e.g. a custom model set elsewhere) shows
        // as its raw id, not "Default".
        return newSessionModels.first { $0.value == preferred }?.displayName ?? preferred
    }

    // MARK: - Effort

    private var effortChip: some View {
        chip(icon: "gauge.with.needle", label: effortLabel, textColor: Theme.ink) {
            optionButton("CLI default", isSelected: app.preferredEffort == nil) {
                app.preferredEffort = nil
            }
            ForEach(EffortPickerMenu.fallbackLevels, id: \.self) { level in
                optionButton(level.capitalized, isSelected: app.preferredEffort == level) {
                    app.preferredEffort = level
                }
            }
        }
        .help("Model effort — lower is faster")
    }

    private var effortLabel: String {
        app.preferredEffort?.capitalized ?? "Default"
    }

    // MARK: - Permission mode

    private var permissionChip: some View {
        chip(icon: "lock.shield", label: permissionLabel, textColor: Theme.ink) {
            optionButton("CLI default", isSelected: app.preferredPermissionMode == nil) {
                app.preferredPermissionMode = nil
            }
            ForEach(PermissionPickerMenu.modes, id: \.mode) { entry in
                optionButton(entry.title,
                             isSelected: app.preferredPermissionMode == entry.mode) {
                    app.preferredPermissionMode = entry.mode
                }
            }
        }
        .help("Permission mode — applied at launch")
    }

    private var permissionLabel: String {
        PermissionPickerMenu.modes
            .first { $0.mode == app.preferredPermissionMode }?.title ?? "Default"
    }

    // MARK: - Shared

    @ViewBuilder
    private func optionButton(
        _ title: String, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func chip<Content: View>(
        icon: String, label: String, textColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            ChipLabel(icon: icon, label: label, textColor: textColor)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
