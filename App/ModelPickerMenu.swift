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
                    if option.value == session.currentModel {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
                .help(option.optionDescription ?? "")
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
