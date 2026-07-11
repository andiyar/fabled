import SwiftUI
import ClaudeKit
import FabledCore

/// One timeline row. `session` is nil in read-only history.
struct TimelineItemView: View {
    let item: TimelineItem
    let session: ChatSession?

    var body: some View {
        switch item {
        case .userMessage(_, let text):
            UserBubble(text: text)
        case .assistantText(_, let markdown, let isStreaming):
            AssistantTextView(markdown: markdown, isStreaming: isStreaming)
        case .toolCall(let id, let name, let summary, let input, let result, let isError, let isRunning):
            // Reads the whole subagentTimelines property (Observation tracks
            // per stored property), so every visible tool row re-renders per
            // parented event — bounded by LazyVStack's visible rows; revisit
            // if a busy subagent janks the transcript (T11 review).
            ToolCallCard(id: id, name: name, summary: summary, input: input,
                         result: result, isError: isError, isRunning: isRunning,
                         subagentSteps: session?.subagentTimelines[id]?.count)
        case .thinking(let id, let text, let isStreaming):
            ThinkingItemView(id: id, text: text, isStreaming: isStreaming)
        case .permission(_, let request, let resolution):
            // Static status row — the interactive card renders in ComposerView while pending.
            PermissionStatusView(request: request, resolution: resolution)
        case .turnSummary(_, let result):
            TurnSummaryView(result: result)
        case .notice(_, let text):
            NoticeView(text: text)
        case .raw(let id, let type, let raw):
            RawEventView(id: id, type: type, raw: raw)
        }
    }
}

struct UserBubble: View {
    let text: String
    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .textSelection(.enabled)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.quaternary.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct AssistantTextView: View {
    let markdown: String
    let isStreaming: Bool

    var body: some View {
        Text(attributed)
            .font(Theme.assistantFont())
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isStreaming ? 0.85 : 1)
    }

    private var attributed: AttributedString {
        // Ledgered decision: AttributedString first, no markdown package.
        (try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }
}

/// One-line tool row; all detail opens in the side inspector. Deliberately
/// stateless — the old DisclosureGroup's @State reset when LazyVStack
/// recycled rows (FOLLOWUPS rider, resolved by this design).
struct ToolCallCard: View {
    let id: String
    let name: String
    let summary: String
    let input: JSONValue
    let result: JSONValue?
    let isError: Bool?
    let isRunning: Bool
    /// "N steps" chip for Task/Agent calls with routed subagent activity.
    let subagentSteps: Int?
    @Environment(\.inspectItem) private var inspectItem

    var body: some View {
        HStack(spacing: 6) {
            ToolStatusIcon(isError: isError, isRunning: isRunning)
            Text(name).fontWeight(.medium)
            Text(summary).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            if let subagentSteps, subagentSteps > 0 {
                Text(subagentSteps == 1 ? "1 step" : "\(subagentSteps) steps")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            if let diff = DiffCache.shared.diff(id: id, toolName: name, input: input) {
                DiffCountChips(added: diff.added, removed: diff.removed)
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .font(.callout)
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        // Tap gesture instead of a Button: a plain Button's action is NOT
        // delivered reliably in these row contexts — the inspect action lives
        // in an environment value whose owning view re-renders frequently
        // (live stream ticks; the history view re-inits ~1/s from sidebar
        // reindex), and per-render invalidation cancels the Button's mouse-up
        // press dispatch. Real-mouse evidence 2026-07-10: Button rows were
        // intermittent/delayed/dead while quick chevron clicks survived (short
        // press duration); TapGesture delivery was verified firing in this
        // exact context (2026-07-09). The gesture + contentShape sit AFTER
        // padding/background so the entire visible card is the hit target —
        // inside the padding they leave a dead 8 pt ring around every row.
        .contentShape(Rectangle())
        .onTapGesture { inspectItem?(id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help("Show full input/output in the inspector")
    }
}

struct PermissionStatusView: View {
    let request: PermissionRequest
    let resolution: PermissionDecision?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text(PermissionPrompt.commandSummary(for: request))
                .font(.system(.callout, design: .monospaced)).lineLimit(1)
            Spacer()
            switch resolution {
            case .allow: Text("Allowed").foregroundStyle(.green)
            case .deny: Text("Denied").foregroundStyle(.red)
            case nil: Text("Awaiting approval").foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .padding(8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct TurnSummaryView: View {
    let result: TurnResult
    var body: some View {
        HStack(spacing: 8) {
            if result.isError {
                Text(result.subtype.replacingOccurrences(of: "_", with: " "))
                    .foregroundStyle(.orange)
            }
            if let cost = result.totalCostUSD {
                Text(String(format: "$%.4f", cost))
            }
            if let ms = result.durationMS {
                Text(String(format: "%.1fs", ms / 1000))
            }
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct NoticeView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
    }
}

struct RawEventView: View {
    let id: String
    let type: String
    let raw: JSONValue
    @Environment(\.inspectItem) private var inspectItem

    var body: some View {
        HStack(spacing: 6) {
            Label(type, systemImage: "questionmark.square.dashed")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(6)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
        // Same rationale as ToolCallCard: TapGesture (not Button) so render
        // churn can't cancel activation, applied outside padding/background so
        // the whole card is the hit target.
        .contentShape(Rectangle())
        .onTapGesture { inspectItem?(id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .help("Show raw event in the inspector")
    }
}

/// Collapsed tool-run row (digest §2a). Expansion state lives on the
/// container (expandedGroups set) — never per-row @State (4a scar).
struct ToolGroupRow: View {
    let id: String
    let items: [TimelineItem]
    let summary: String
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceS) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(summary).fontWeight(.medium)
                Text("\(items.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
                Spacer(minLength: 4)
            }
            .font(.callout)
            .padding(Theme.spaceS)
            .background(.quinary, in: RoundedRectangle(cornerRadius: Theme.radiusCard))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(Theme.snap) { toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(summary), \(isExpanded ? "expanded" : "collapsed")")
            .help(isExpanded ? "Collapse this run" : "Expand \(items.count) steps")
            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spaceS) {
                    // Grouped runs never contain Task/Agent rows (anchors are
                    // excluded from grouping), so no subagent plumbing here.
                    // T14's signature sweep updates this call site.
                    ForEach(items) { item in
                        TimelineItemView(item: item, session: nil)
                    }
                }
                .padding(.leading, Theme.spaceL)
            }
        }
    }
}
