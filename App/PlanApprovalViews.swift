import SwiftUI
import FabledCore

/// Composer-slot announcement for a pending ExitPlanMode gate.
struct PlanApprovalCard: View {
    let approval: PlanApproval
    let review: () -> Void
    let approve: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard.fill").foregroundStyle(Theme.clay)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude proposes a plan").fontWeight(.semibold)
                Text(planTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button("Review Plan…", action: review)
                .keyboardShortcut(.return, modifiers: .command)
            Button("Approve", action: approve)
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
        }
        .padding(12)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.clay.opacity(0.5)))
    }

    private var planTitle: String {
        approval.plan.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map { $0.trimmingCharacters(in: .init(charactersIn: "# ")) }
            ?? "Untitled plan"
    }
}

/// Full-plan review sheet: approve (⌘⏎) or send revision feedback.
struct PlanReviewSheet: View {
    let approval: PlanApproval
    let approve: () -> Void
    let reject: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var feedback = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Proposed plan", systemImage: "list.clipboard")
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Close — decide later")
            }
            ScrollView {
                // Inline-only markdown (ledgered AttributedString decision):
                // headings render as plain lines — readable, not pretty.
                // Serif matches Claude's voice.
                AssistantTextView(markdown: approval.plan, isStreaming: false)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            TextField("Feedback (sent with Request Changes)",
                      text: $feedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            HStack {
                Button("Request Changes") {
                    reject(feedback)
                    dismiss()
                }
                Spacer()
                Button("Approve Plan") {
                    approve()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.clay)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(minWidth: 540, idealWidth: 640, minHeight: 420, idealHeight: 560)
    }
}
