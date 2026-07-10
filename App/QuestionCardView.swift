import SwiftUI
import FabledCore

/// Native rendering for AskUserQuestion (probe findings 1-3). Claude waits
/// on this card — it must always offer Skip so the turn can proceed.
struct QuestionCardView: View {
    let prompt: QuestionPrompt
    let respond: ([String: String]) -> Void
    let skip: () -> Void

    @State private var selections: [String: Set<String>] = [:]
    @State private var otherText: [String: String] = [:]

    /// One single-select question = click-to-answer, no Submit ceremony.
    private var isSingleShot: Bool {
        prompt.questions.count == 1 && !(prompt.questions.first?.multiSelect ?? false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.bubble.fill")
                    .foregroundStyle(Theme.clay)
                Text("Claude asks").fontWeight(.semibold)
                Spacer()
                Button("Skip", action: skip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .help("Continue without answering")
            }
            ForEach(prompt.questions) { question in
                questionBlock(question)
            }
            if !isSingleShot {
                HStack {
                    Spacer()
                    Button("Answer") { submit() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.clay)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!isComplete)
                }
            }
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.clay.opacity(0.5)))
    }

    @ViewBuilder
    private func questionBlock(_ question: QuestionPrompt.Question) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if !question.header.isEmpty {
                    Text(question.header)
                        .font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(question.text).font(.callout)
            }
            ForEach(question.options, id: \.label) { option in
                optionRow(question: question, option: option)
            }
            TextField("Other…", text: otherBinding(question))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit { if isSingleShot { submit() } }
        }
    }

    private func optionRow(question: QuestionPrompt.Question,
                           option: QuestionPrompt.Option) -> some View {
        let isSelected = selections[question.text, default: []].contains(option.label)
        return Button {
            toggle(question: question, option: option.label)
            if isSingleShot { submit() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: question.multiSelect
                    ? (isSelected ? "checkmark.square.fill" : "square")
                    : (isSelected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(isSelected ? Theme.clay : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(question: QuestionPrompt.Question, option: String) {
        var selected = selections[question.text, default: []]
        if question.multiSelect {
            if selected.contains(option) { selected.remove(option) }
            else { selected.insert(option) }
        } else {
            selected = [option]
        }
        selections[question.text] = selected
    }

    private func otherBinding(_ question: QuestionPrompt.Question) -> Binding<String> {
        Binding(get: { otherText[question.text] ?? "" },
                set: { otherText[question.text] = $0 })
    }

    private func answerText(_ question: QuestionPrompt.Question) -> String? {
        let other = (otherText[question.text] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Catalog order, not click order — multi-select joins with ", "
        // (probe finding 2). Free text rides along as one more value.
        var parts = question.options.map(\.label)
            .filter { selections[question.text, default: []].contains($0) }
        if !other.isEmpty { parts.append(other) }
        guard !parts.isEmpty else { return nil }
        return question.multiSelect ? parts.joined(separator: ", ") : parts[0]
    }

    private var isComplete: Bool {
        prompt.questions.allSatisfy { answerText($0) != nil }
    }

    private func submit() {
        var answers: [String: String] = [:]
        for question in prompt.questions {
            guard let answer = answerText(question) else { return }
            answers[question.text] = answer
        }
        respond(answers)
    }
}
