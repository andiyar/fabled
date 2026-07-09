import SwiftUI
import FabledCore

struct ConversationView: View {
    let session: ChatSession
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if let note = session.versionNote {
                Text(note)
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(4)
                    .background(.yellow.opacity(0.15))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.timeline) { item in
                        TimelineItemView(item: item, session: session)
                    }
                    if session.isThinking {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(Theme.assistantFont(.callout)).italic()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
            .defaultScrollAnchor(.bottom)
            Divider()
            // Minimal inline composer — Task 11 replaces this block with
            // ComposerView (multiline, shortcuts, stop button).
            HStack {
                TextField("Message Claude…", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit(sendDraft)
                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2).foregroundStyle(Theme.clay)
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
        .navigationTitle(session.title)
        .navigationSubtitle(session.workingDirectory.path)
    }

    private func sendDraft() {
        session.send(draft)
        draft = ""
    }
}
