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
                    // macOS renders a two-Text VStack label as title + subtitle,
                    // so surface the resolved version under the friendly name
                    // (Ben wants to see that e.g. "opus" = claude-opus-4-8).
                    if option.value == session.currentModel {
                        Label {
                            labelBody(for: option)
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        labelBody(for: option)
                    }
                }
                .help(option.optionDescription ?? "")
            }
            Divider()
            // Every catalog entry by its raw id — the by-id view Ben asked for.
            Menu("All Models") {
                ForEach(session.models) { option in
                    Button {
                        session.setModel(option.value)
                    } label: {
                        let id = option.resolvedModel ?? option.value
                        if option.value == session.currentModel {
                            Label(id, systemImage: "checkmark")
                        } else {
                            Text(id)
                        }
                    }
                }
            }
            Divider()
            Button("Custom Model…") { isCustomSheetPresented = true }
        } label: {
            Label(currentDisplayName, systemImage: "cpu")
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

    /// Friendly name, plus the resolved version as a subtitle when it adds
    /// information over the display name.
    @ViewBuilder
    private func labelBody(for option: ModelOption) -> some View {
        let version = option.resolvedModel ?? option.value
        VStack(alignment: .leading) {
            Text(option.displayName)
            if version != option.displayName {
                Text(version).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var currentDisplayName: String {
        session.models.first { $0.value == session.currentModel }?.displayName
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
