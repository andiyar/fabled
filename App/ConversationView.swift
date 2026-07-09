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
            // GeometryReader + minHeight makes short conversations lay out from
            // the top (minHeight fills the viewport, top-aligned) while long
            // ones still overflow and follow the bottom anchor while streaming.
            GeometryReader { geo in
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
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .defaultScrollAnchor(.bottom)
            }
            Divider()
            ComposerView(session: session)
        }
        .navigationTitle(session.title)
        .navigationSubtitle(session.workingDirectory.path)
        .toolbar {
            ToolbarItemGroup {
                ModelPickerMenu(session: session)
                Picker("Permissions", selection: Binding(
                    get: { session.permissionMode },
                    set: { session.setPermissionMode($0) }
                )) {
                    Text("Default").tag("default")
                    Text("Plan").tag("plan")
                    Text("Accept Edits").tag("acceptEdits")
                    Text("Bypass Permissions").tag("bypassPermissions")
                }
                .pickerStyle(.menu)
                if session.cumulativeCostUSD > 0 {
                    Text(String(format: "$%.2f", session.cumulativeCostUSD))
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}
