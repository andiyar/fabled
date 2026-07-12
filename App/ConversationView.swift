import SwiftUI
import FabledCore

struct ConversationView: View {
    @Environment(AppModel.self) private var app
    let session: ChatSession
    /// Hoisted to RootView so an open inspector survives per-session hierarchy
    /// recreation (the deliberate T6 behavior). Owned there, bound here.
    @Binding var isInspectorPresented: Bool
    @State private var inspectedID: String?
    /// Navigation trail of previously inspected ids: any click that switches
    /// the panel to a different item pushes the old one, and the panel's Back
    /// button pops it (drill-down into subagent sub-rows is the motivating
    /// case — Ben, 2026-07-10 live smoke — but the trail is deliberately
    /// browser-like across plain row clicks too).
    @State private var inspectBackStack: [String] = []
    @State private var expandedGroups: Set<String> = []

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
                        ForEach(TimelineDisplay.grouped(session.timeline)) { row in
                            switch row {
                            case .item(let item):
                                TimelineItemView(item: item,
                                                 subagentSteps: item.toolCallID
                                                     .flatMap { session.subagentTimelines[$0]?.count })
                            case .toolGroup(let id, let items, let summary):
                                ToolGroupRow(
                                    id: id, items: items, summary: summary,
                                    isExpanded: expandedGroups.contains(id),
                                    toggle: {
                                        if expandedGroups.contains(id) {
                                            expandedGroups.remove(id)
                                        } else {
                                            expandedGroups.insert(id)
                                        }
                                    })
                            }
                        }
                        if session.isWorking {
                            StreamStatusRow(session: session)
                        }
                    }
                    .padding()
                    .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height, alignment: .top)
                }
                .defaultScrollAnchor(.bottom)
            }
            let checklistRows = session.sessionTasks.isEmpty
                ? session.todos.map(\.checklistRow)
                : session.sessionTasks.map(\.checklistRow)
            if !checklistRows.isEmpty {
                TodoChecklistView(rows: checklistRows)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .frame(maxWidth: Theme.contentMaxWidth)
            }
            // The composer bar draws its own top hairline (matching the locked
            // mockup's single separator) — no extra Divider here.
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
        // Clearing the selection (the panel's ✕) ends the trail; ⌥⌘I only
        // toggles presentation and deliberately preserves selection + trail
        // (the two-affordance split from the T6 design).
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

/// Under-stream status line: thinking ticker while deltas flow, and a
/// client-timed liveness note when the wire goes quiet mid-turn (there is
/// no heartbeat during tool execution — 4a probe finding 8; the opus-outage
/// gate feedback is why silence must be labeled).
private struct StreamStatusRow: View {
    let session: ChatSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(label(now: context.date))
                    .font(Theme.assistantFont(.callout)).italic()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
        }
    }

    private func label(now: Date) -> String {
        if session.isThinking {
            if let tokens = session.thinkingTokens, tokens > 0 {
                return "Thinking… ~\(tokens) tokens"
            }
            return "Thinking…"
        }
        if let last = session.lastEventAt {
            let quiet = Int(now.timeIntervalSince(last))
            if quiet >= 20 {
                return "Still working — no response for \(quiet)s…"
            }
        }
        return "Working…"
    }
}
