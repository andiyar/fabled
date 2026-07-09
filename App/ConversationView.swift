import SwiftUI
import FabledCore

struct ConversationView: View {
    let session: ChatSession

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
            ComposerView(session: session)
        }
        .navigationTitle(session.title)
        .navigationSubtitle(session.workingDirectory.path)
    }
}
