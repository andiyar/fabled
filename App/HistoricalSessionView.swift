import SwiftUI
import ClaudeKit
import FabledCore

struct HistoricalSessionView: View {
    @Environment(AppModel.self) private var app
    let summary: SessionSummary
    @State private var items: [TimelineItem]?
    @State private var inspectedID: String?
    @State private var isInspectorPresented = false
    @State private var expandedGroups: Set<String> = []
    /// Type-to-resume draft (UX-LEDGER row 16): typing here and sending
    /// reattaches this session instead of making Ben hunt for Continue.
    @State private var draft = ""
    /// On-disk subagent sub-timelines keyed by parent Task tool_use id — the
    /// historical analog of ChatSession.subagentTimelines (4b Task 14).
    @State private var subagentTimelines: [String: [TimelineItem]] = [:]
    /// Drill-down trail, mirroring ConversationView: a click that switches the
    /// panel pushes the old selection; the panel's Back button pops it. Ben
    /// asked for the same browser-like Back on the live side (2026-07-10).
    @State private var inspectBackStack: [String] = []

    /// Resolves the inspected id against the main timeline AND all subagent
    /// sub-timelines (drilled-in sub rows are inspectable too — mirrors
    /// ConversationView).
    private var inspectedItem: TimelineItem? {
        guard let inspectedID else { return nil }
        if let item = (items ?? []).first(where: { $0.id == inspectedID }) { return item }
        for timeline in subagentTimelines.values {
            if let item = timeline.first(where: { $0.id == inspectedID }) { return item }
        }
        return nil
    }

    /// One action for the transcript rows and the inspector's sub-rows.
    /// Injected directly onto the concrete rows ScrollView (main timeline) and
    /// handed explicitly to InspectorPanel (drill-down) — never relied on via
    /// inheritance across the `.inspector` presentation boundary.
    /// `id` gives the action a stable Equatable identity so the environment
    /// value does not churn per render (see InspectItemAction / the row-click
    /// note in TimelineItemViews.swift for WHY that matters).
    private var inspectAction: InspectItemAction {
        InspectItemAction(id: "historical-\(summary.id)") { id in
            if let current = inspectedID, current != id {
                inspectBackStack.append(current)
            }
            inspectedID = id
            isInspectorPresented = true
        }
    }

    var body: some View {
        // Presentation/structural modifiers (.inspector, .toolbar,
        // .navigationTitle, .task) attach to this always-present concrete
        // VStack, mirroring ConversationView's proven-working shape, rather than
        // to a `Group` whose conditional child identity swaps (ProgressView →
        // ScrollView) once `.task` loads. Attaching a presentation modifier to a
        // stable concrete root — not a Group over a swapping branch — is the
        // boring, reliable shape; the loading/loaded conditional nests INSIDE.
        VStack(spacing: 0) {
            if let items {
                // Match ConversationView: short transcripts lay out from the top
                // (minHeight fills the viewport), long ones follow the bottom.
                GeometryReader { geo in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(TimelineDisplay.grouped(items)) { row in
                                switch row {
                                case .item(let item):
                                    TimelineItemView(item: item,
                                                     subagentSteps: item.toolCallID
                                                         .flatMap { subagentTimelines[$0]?.count })
                                case .toolGroup(let id, let groupItems, let summary):
                                    ToolGroupRow(
                                        id: id, items: groupItems, summary: summary,
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
                        }
                        .padding()
                        .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                    .defaultScrollAnchor(.bottom)
                }
            } else {
                ProgressView("Loading transcript…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider().overlay(Theme.hairline)
            resumeComposer
        }
        .navigationTitle(summary.title)
        .navigationSubtitle(summary.project.displayName)
        // Top-level chain, above .inspector — mirrors ConversationView, the
        // empirically working configuration (see 2026-07-09 note there).
        .environment(\.inspectItem, inspectAction)
        .inspector(isPresented: $isInspectorPresented) {
            // Threaded in explicitly — presented inspector content does not
            // inherit the transcript's `.environment(\.inspectItem)`.
            InspectorPanel(item: inspectedItem,
                           subagentItems: inspectedID.flatMap { subagentTimelines[$0] },
                           inspectItem: inspectAction,
                           inspectedID: $inspectedID,
                           onBack: inspectBackStack.isEmpty ? nil : {
                               inspectedID = inspectBackStack.popLast()
                           })
                .inspectorColumnWidth(min: 300, ideal: 420, max: 640)
        }
        // Clearing the selection (the panel's ✕) ends the trail; ⌥⌘I only
        // toggles presentation and preserves selection + trail (mirrors
        // ConversationView's two-affordance split).
        .onChange(of: inspectedID) { _, new in
            if new == nil { inspectBackStack.removeAll() }
        }
        .toolbar {
            ToolbarItemGroup {
                // Independent presentation-path affordance (matches
                // ConversationView) — verifiable without clicking a row.
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                }
                .help("Toggle inspector")
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .task(id: summary.id) {
            let requested = summary.id
            items = nil
            expandedGroups.removeAll()
            // A stale trail must never walk Back into another summary's items.
            subagentTimelines = [:]
            inspectBackStack = []
            // Cross-summary fallback ids ("line-N") collide — mirror
            // ConversationView's reset so a stale selection can't silently
            // resolve to another summary's row.
            inspectedID = nil
            let loaded = await app.historicalTimeline(for: summary)
            // Rapid switching: a slow load must not land on a newer selection
            // (FOLLOWUPS stale-assignment window).
            guard !Task.isCancelled, requested == summary.id else { return }
            items = loaded
            // Drill-down data loads AFTER the main items, same race guard: the
            // on-disk read is heavier, and rows work without it (chips just
            // stay absent until it lands).
            let subs = await app.historicalSubagentTimelines(for: summary)
            guard !Task.isCancelled, requested == summary.id else { return }
            subagentTimelines = subs
        }
    }

    // MARK: - Resume composer (UX-LEDGER row 16: type-to-resume)

    /// Typing here and sending reattaches this session (the same Continue
    /// path — one-process invariant) and delivers the message, so Ben can
    /// just pick up the conversation instead of hunting for the Continue
    /// button. Styling mirrors WelcomeView's start composer for consistency.
    private var resumeComposer: some View {
        VStack(alignment: .leading, spacing: Theme.spaceM) {
            TextField("Message to pick up where you left off…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...8)
                .onSubmit(sendAndResume)
            HStack(spacing: Theme.spaceS) {
                ComposerChips()
                Spacer(minLength: Theme.spaceS)
                resumeSendButton
            }
        }
        .padding(Theme.spaceM)
        .background(Theme.surfaceSide)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resumeSendButton: some View {
        Button(action: sendAndResume) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.ground)
                .frame(width: 30, height: 30)
                .background(Theme.clay, in: RoundedRectangle(cornerRadius: 8))
                .opacity(canSendResume ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!canSendResume)
    }

    private var canSendResume: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendAndResume() {
        guard canSendResume else { return }
        // Clear only on delivery — a failed spawn keeps Ben's typed prose
        // (he resumes with novel/thesis paragraphs) instead of wiping it.
        Task { if await app.resumeAndSend(summary, text: draft) { draft = "" } }
    }
}
