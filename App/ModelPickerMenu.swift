import SwiftUI
import FabledCore

/// Catalog-driven (initialize response, probe finding 9) + free-text custom
/// IDs — `--model` accepts full model IDs, so the picker must too.
struct ModelPickerMenu: View {
    let session: ChatSession
    @State private var isCustomSheetPresented = false
    @State private var customModel = ""

    var body: some View {
        Menu {
            ForEach(session.models) { option in
                Button {
                    session.setModel(option.value)
                } label: {
                    // macOS menus DON'T render a second Text in a VStack label,
                    // so use a single-line label that folds the resolved id in
                    // (Ben wants to see that e.g. "opus" = claude-opus-4-8).
                    if isCurrent(option) {
                        Label(labelText(for: option), systemImage: "checkmark")
                    } else {
                        Text(labelText(for: option))
                    }
                }
                .help(option.optionDescription ?? "")
            }
            Divider()
            // Every distinct resolved id — the by-id view Ben asked for. Dedupe
            // by resolved id so aliases that map to the same model (e.g. Default
            // and Opus → claude-opus-4-8[1m]) don't produce duplicate rows.
            Menu("All Models") {
                ForEach(uniqueResolvedOptions, id: \.id) { option in
                    Button {
                        session.setModel(option.value)
                    } label: {
                        if isCurrent(option) {
                            Label(labelText(for: option), systemImage: "checkmark")
                        } else {
                            Text(labelText(for: option))
                        }
                    }
                }
            }
            Divider()
            Button("Custom Model…") { isCustomSheetPresented = true }
        } label: {
            Label(currentDisplayName, systemImage: "cpu")
                .labelStyle(.titleAndIcon)
        }
        .sheet(isPresented: $isCustomSheetPresented) {
            VStack(spacing: 12) {
                Text("Custom model ID").font(.headline)
                TextField("e.g. claude-sonnet-5", text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)
                    .onSubmit(applyCustomModel)
                    .onAppear { customModel = "" }
                HStack {
                    Button("Cancel") { isCustomSheetPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Switch", action: applyCustomModel)
                        .buttonStyle(.borderedProminent).tint(Theme.clay)
                        .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(20)
        }
    }

    /// True when this option is the session's current model. `currentModel` may
    /// hold a catalog alias (user picked "opus") OR a full model id (from the
    /// system init event, e.g. "claude-opus-4-8"), so match on either.
    private func isCurrent(_ option: ModelOption) -> Bool {
        guard let current = session.currentModel else { return false }
        return option.value == current || option.resolvedModel == current
    }

    /// Single-line label: friendly name alone when the resolved id adds nothing,
    /// else "Display Name — resolved-id" so the mapping is visible in one Text.
    private func labelText(for option: ModelOption) -> String {
        guard let resolved = option.resolvedModel,
              resolved != option.displayName,
              resolved != option.value else {
            return option.displayName
        }
        return "\(option.displayName) — \(resolved)"
    }

    /// Catalog merged with the hardcoded known-models list (catalog first and
    /// authoritative), deduped by resolved id, keeping the first occurrence.
    private var uniqueResolvedOptions: [ModelOption] {
        var seen = Set<String>()
        return ModelOption.merged(catalog: session.models).filter { option in
            seen.insert(option.resolvedModel ?? option.value).inserted
        }
    }

    private var currentDisplayName: String {
        session.models.first { isCurrent($0) }?.displayName
            ?? session.currentModel
            ?? "Model"
    }

    private func applyCustomModel() {
        let value = customModel.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return }
        session.setModel(value)
        isCustomSheetPresented = false
    }
}
