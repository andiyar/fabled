import SwiftUI
import FabledCore

struct ComposerView: View {
    let session: ChatSession
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if let gate = session.pendingGate {
                switch gate {
                case .permission(let request):
                    PermissionCardView(request: request) { decision in
                        session.respond(to: request, decision: decision)
                    }
                    .id(request.requestID)
                case .question(let prompt):
                    // Placeholder until Task 8's QuestionCardView.
                    HStack {
                        Text(prompt.questions.first?.text ?? "Claude has a question")
                            .font(.callout)
                        Spacer()
                        Button("Skip") { session.skipQuestions(prompt) }
                    }
                    .padding(10)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                case .planApproval(let approval):
                    // Placeholder until Task 9's PlanApprovalViews.
                    HStack {
                        Text("Claude proposes a plan").font(.callout)
                        Spacer()
                        Button("Reject") { session.rejectPlan(approval, feedback: nil) }
                        Button("Approve") { session.approvePlan(approval) }
                            .buttonStyle(.borderedProminent).tint(Theme.clay)
                    }
                    .padding(10)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Claude…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .onSubmit(send)   // Return sends; ⌥Return inserts a newline
                if session.isWorking {
                    Button(action: session.interrupt) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Interrupt (⌘.)")
                    .keyboardShortcut(".", modifiers: .command)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(canSend ? Theme.clay : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                // ⌘⏎ belongs to the permission card while one is pending.
                .keyboardShortcut(session.pendingGate == nil
                    ? KeyboardShortcut(.return, modifiers: .command) : nil)
            }
        }
        .padding(10)
        .onAppear { isFocused = true }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.hasEnded
    }

    private func send() {
        guard canSend else { return }
        session.send(draft)
        draft = ""
    }
}
