import SwiftUI
import FabledCore

/// A reusable model / effort / permission-mode chip row, bound to three
/// values the caller owns — it never writes app state directly.
///
/// The start composer (WelcomeView) binds these to `app.preferred*`, the
/// sticky spawn defaults (UX-LEDGER row 22): picking a value there drives
/// the next new session's launch.
///
/// The resume composer (HistoricalSessionView) binds these to a past chat's
/// own state instead — the model + permission mode recovered from its
/// transcript, plus the live effort default — so opening an old chat shows
/// what it will ACTUALLY resume on, not misleading "Default" chips (gate
/// rework, the "I don't even know what the last model was" feedback).
struct ComposerChips: View {
    @Binding var model: String?
    @Binding var effort: String?
    @Binding var permission: String?

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
            optionButton("Default", isSelected: model == nil) {
                model = nil
            }
            ForEach(newSessionModels) { option in
                optionButton(option.displayName,
                             isSelected: model == option.value) {
                    model = option.value
                }
            }
        }
        .help("Model")
    }

    private var modelLabel: String {
        guard let model else { return "Default" }
        // A persisted-but-unknown id (e.g. a custom model set elsewhere, or a
        // transcript's model that has since been retired) shows as its raw
        // id, not "Default".
        return newSessionModels.first { $0.value == model }?.displayName ?? model
    }

    // MARK: - Effort

    private var effortChip: some View {
        chip(icon: "gauge.with.needle", label: effortLabel, textColor: Theme.ink) {
            optionButton("CLI default", isSelected: effort == nil) {
                effort = nil
            }
            ForEach(EffortPickerMenu.fallbackLevels, id: \.self) { level in
                optionButton(level.capitalized, isSelected: effort == level) {
                    effort = level
                }
            }
        }
        .help("Model effort — lower is faster")
    }

    private var effortLabel: String {
        effort?.capitalized ?? "Default"
    }

    // MARK: - Permission mode

    private var permissionChip: some View {
        chip(icon: "lock.shield", label: permissionLabel, textColor: Theme.ink) {
            optionButton("CLI default", isSelected: permission == nil) {
                permission = nil
            }
            ForEach(PermissionPickerMenu.modes, id: \.mode) { entry in
                optionButton(entry.title,
                             isSelected: permission == entry.mode) {
                    permission = entry.mode
                }
            }
        }
        .help("Permission mode — applied at launch")
    }

    private var permissionLabel: String {
        PermissionPickerMenu.modes
            .first { $0.mode == permission }?.title ?? "Default"
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
