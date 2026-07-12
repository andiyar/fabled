import SwiftUI
import FabledCore

/// The composer chip row: model, effort, and permission-mode chips styled to
/// match the locked chip look (WelcomeView's `projectChip`). Two modes via
/// `Target`:
///  - `.newSession` — no live session yet. Chips write the persisted spawn
///    defaults (`app.preferred*`) that `AppModel.newSession` reads when it
///    spawns `claude` (UX-LEDGER row 22, B1.4).
///  - `.live` — an existing session. Chips drive it the same way
///    ModelPickerMenu/EffortPickerMenu/PermissionPickerMenu's "This session"
///    sections already do. Not wired into any view yet — B1.4 only adds the
///    home composer; a later task will have the conversation composer adopt
///    this case.
struct ComposerChips: View {
    enum Target {
        case newSession
        case live(ChatSession)
    }
    let target: Target
    @Environment(AppModel.self) private var app

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
            switch target {
            case .newSession:
                optionButton("Default", isSelected: app.preferredModel == nil) {
                    app.preferredModel = nil
                }
                ForEach(ModelOption.merged(catalog: [])) { option in
                    optionButton(option.displayName,
                                 isSelected: app.preferredModel == option.value) {
                        app.preferredModel = option.value
                    }
                }
            case .live(let session):
                ForEach(session.models) { option in
                    optionButton(option.displayName,
                                 isSelected: isCurrentModel(option, in: session)) {
                        session.setModel(option.value)
                    }
                }
            }
        }
        .help("Model")
    }

    private var modelLabel: String {
        switch target {
        case .newSession:
            guard let preferred = app.preferredModel,
                  let match = ModelOption.merged(catalog: [])
                    .first(where: { $0.value == preferred })
            else { return "Default" }
            return match.displayName
        case .live(let session):
            return session.models.first { isCurrentModel($0, in: session) }?.displayName
                ?? session.currentModel
                ?? "Model"
        }
    }

    /// Mirrors ModelPickerMenu.isCurrent: `currentModel` may hold a catalog
    /// alias (user picked "opus") OR a full resolved id (from the system
    /// init event), so match on either.
    private func isCurrentModel(_ option: ModelOption, in session: ChatSession) -> Bool {
        guard let current = session.currentModel else { return false }
        return option.value == current || option.resolvedModel == current
    }

    // MARK: - Effort

    private var effortChip: some View {
        chip(icon: "gauge.with.needle", label: effortLabel, textColor: Theme.ink) {
            switch target {
            case .newSession:
                optionButton("CLI default", isSelected: app.preferredEffort == nil) {
                    app.preferredEffort = nil
                }
                ForEach(EffortPickerMenu.fallbackLevels, id: \.self) { level in
                    optionButton(level.capitalized, isSelected: app.preferredEffort == level) {
                        app.preferredEffort = level
                    }
                }
            case .live(let session):
                ForEach(EffortPickerMenu.fallbackLevels, id: \.self) { level in
                    optionButton(level.capitalized, isSelected: session.currentEffort == level) {
                        session.setEffort(level)
                    }
                }
            }
        }
        .help("Model effort — lower is faster")
        .disabled(isLiveGated)
    }

    private var effortLabel: String {
        switch target {
        case .newSession: return app.preferredEffort?.capitalized ?? "Default"
        case .live(let session): return session.currentEffort?.capitalized ?? "Effort"
        }
    }

    // MARK: - Permission mode

    private var permissionChip: some View {
        chip(icon: "lock.shield", label: permissionLabel, textColor: Theme.ink) {
            switch target {
            case .newSession:
                optionButton("CLI default", isSelected: app.preferredPermissionMode == nil) {
                    app.preferredPermissionMode = nil
                }
                ForEach(PermissionPickerMenu.modes, id: \.mode) { entry in
                    optionButton(entry.title,
                                 isSelected: app.preferredPermissionMode == entry.mode) {
                        app.preferredPermissionMode = entry.mode
                    }
                }
            case .live(let session):
                ForEach(PermissionPickerMenu.modes, id: \.mode) { entry in
                    optionButton(entry.title, isSelected: session.permissionMode == entry.mode) {
                        session.setPermissionMode(entry.mode)
                    }
                }
            }
        }
        .help("Permission mode — the New sessions choice is applied at launch")
        .disabled(isLiveGated)
    }

    private var permissionLabel: String {
        switch target {
        case .newSession:
            return PermissionPickerMenu.modes
                .first { $0.mode == app.preferredPermissionMode }?.title ?? "Default"
        case .live(let session):
            return PermissionPickerMenu.modes
                .first { $0.mode == session.permissionMode }?.title ?? "Permissions"
        }
    }

    // MARK: - Shared

    /// A mid-question mode/effort change would race the CLI — same guard as
    /// EffortPickerMenu/PermissionPickerMenu's "This session" sections. Only
    /// meaningful for `.live`; `.newSession` is never gated.
    private var isLiveGated: Bool {
        if case .live(let session) = target {
            return session.pendingGate != nil || session.hasEnded
        }
        return false
    }

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

    /// The locked chip chrome — an exact copy of WelcomeView.projectChip's
    /// label styling. `textColor` is the only per-chip variable: the model
    /// chip reads in bronze, effort and permission read in ink.
    private func chip<Content: View>(
        icon: String, label: String, textColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: Theme.spaceXS) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.accentBronze)
                Text(label)
                    .foregroundStyle(textColor)
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
}
