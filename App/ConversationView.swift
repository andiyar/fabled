import SwiftUI
import FabledCore

struct ConversationView: View {
    let session: ChatSession
    @State private var inspectedID: String?
    @State private var isInspectorPresented = false
    /// Trail of previously inspected ids: drilling from a Task's detail into a
    /// subagent sub-row pushes the Task here, and the panel's Back button pops
    /// it — without this the only way back up is re-clicking the transcript
    /// row (Ben, 2026-07-10 live smoke).
    @State private var inspectBackStack: [String] = []

    /// Resolves the inspected id against the main timeline and all subagent
    /// sub-timelines (sub rows are inspectable too — Task 11).
    private var inspectedItem: TimelineItem? {
        guard let inspectedID else { return nil }
        if let item = session.timeline.first(where: { $0.id == inspectedID }) { return item }
        for timeline in session.subagentTimelines.values {
            if let item = timeline.first(where: { $0.id == inspectedID }) { return item }
        }
        return nil
    }

    /// One action, shared by the transcript rows and the inspector's drill-down
    /// sub-rows. Injected DIRECTLY onto each concrete rows container (below) —
    /// never relied on via inheritance across a `.inspector` presentation
    /// boundary, which does not forward custom `.environment` values.
    private var inspectAction: InspectItemAction {
        // Stable id → Equatable environment value that does not churn per render
        // (see InspectItemAction / the row-activation note in TimelineItemViews).
        InspectItemAction(id: "conversation-\(session.id)") { id in
            if let current = inspectedID, current != id {
                inspectBackStack.append(current)
            }
            inspectedID = id
            isInspectorPresented = true
        }
    }

    /// Always-visible active model: catalog display name when known,
    /// else the raw id the session reported.
    private var activeModelLabel: String {
        guard let current = session.currentModel else { return "" }
        if let match = session.models.first(where: {
            $0.value == current || $0.resolvedModel == current
        }) {
            return match.displayName
        }
        return current
    }

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
                        // 2.1.205+ holds all output (including `system init`)
                        // until the first user turn — without this a fresh
                        // session is an empty pane indistinguishable from a
                        // dead one.
                        if session.timeline.isEmpty && !session.hasEnded {
                            HStack(spacing: 6) {
                                if session.isAwaitingFirstMessage {
                                    Text("Ready — send a message to begin.")
                                } else {
                                    ProgressView().controlSize(.small)
                                    Text("Starting Claude…")
                                }
                            }
                            .font(Theme.assistantFont(.callout)).italic()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 48)
                        }
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
                    .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .defaultScrollAnchor(.bottom)
            }
            if !session.todos.isEmpty {
                TodoChecklistView(todos: session.todos)
                    // Session-scoped identity: RootView reuses this view across
                    // live-session switches, so without it the collapse @State
                    // leaks between sessions (T10 quality review).
                    .id(session.id)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .frame(maxWidth: Theme.contentMaxWidth)
            }
            Divider()
            ComposerView(session: session)
        }
        .navigationTitle(session.title)
        .navigationSubtitle(session.workingDirectory.path)
        // On the top-level chain, ABOVE .inspector — the one attachment point
        // where row activation is empirically reliable (2026-07-09 debugging:
        // attaching this to the rows ScrollView broke Button dispatch there).
        .environment(\.inspectItem, inspectAction)
        .inspector(isPresented: $isInspectorPresented) {
            // `inspectItem` is passed explicitly — the inspector's presented
            // content does not inherit the `.environment(\.inspectItem)` set on
            // the transcript, so the drill-down sub-rows need it handed in.
            InspectorPanel(item: inspectedItem,
                           subagentItems: inspectedID.flatMap { session.subagentTimelines[$0] },
                           inspectItem: inspectAction,
                           inspectedID: $inspectedID,
                           onBack: inspectBackStack.isEmpty ? nil : {
                               inspectedID = inspectBackStack.popLast()
                           })
                .inspectorColumnWidth(min: 300, ideal: 420, max: 640)
        }
        // Dismissing the panel (✕ or ⌥⌘I) ends the drill-down trail; a fresh
        // inspection starts from a clean stack.
        .onChange(of: inspectedID) { _, new in
            if new == nil { inspectBackStack.removeAll() }
        }
        .toolbar {
            ToolbarItemGroup {
                if session.currentModel != nil {
                    Text(activeModelLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .help("Active model")
                }
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
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle inspector")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}
