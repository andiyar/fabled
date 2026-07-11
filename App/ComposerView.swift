import SwiftUI
import FabledCore

struct ComposerView: View {
    let session: ChatSession
    @FocusState private var isFocused: Bool
    @State private var reviewingPlan: PlanApproval?

    var body: some View {
        @Bindable var session = session
        return VStack(spacing: 8) {
            if let gate = session.pendingGate {
                switch gate {
                case .permission(let request):
                    PermissionCardView(request: request) { decision in
                        session.respond(to: request, decision: decision)
                    }
                    .id(request.requestID)
                case .question(let prompt):
                    QuestionCardView(
                        prompt: prompt,
                        respond: { session.answer(prompt, answers: $0) },
                        skip: { session.skipQuestions(prompt) })
                    .id(prompt.request.requestID)
                case .planApproval(let approval):
                    PlanApprovalCard(
                        approval: approval,
                        review: { reviewingPlan = approval },
                        approve: { session.approvePlan(approval) })
                    .id(approval.request.requestID)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message Claude…", text: $session.draft, axis: .vertical)
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
        .sheet(item: $reviewingPlan) { approval in
            PlanReviewSheet(
                approval: approval,
                approve: { session.approvePlan(approval) },
                reject: { session.rejectPlan(approval, feedback: $0) })
        }
        // An aborted turn abandons the gate; a stale sheet must not send
        // decisions into the void (ChatSession's removeGate guard makes such
        // sends no-ops, but the open sheet would still mislead).
        .onChange(of: session.pendingGate?.requestID) {
            if let reviewing = reviewingPlan,
               session.pendingGates.first(where: { $0.requestID == reviewing.request.requestID }) == nil {
                reviewingPlan = nil
            }
        }
    }

    private var canSend: Bool {
        !session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.hasEnded
    }

    private func send() {
        guard canSend else { return }
        session.send(session.draft)
        session.draft = ""
    }
}
