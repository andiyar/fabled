import ClaudeKit

/// One row in the inspector's default Activity list — a single meaningful unit
/// of "what ran". Pure value, no view: `drillID` is a real timeline-item id the
/// inspector already knows how to resolve, so clicking a row opens that item's
/// existing detail.
public struct ActivityRow: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case command, edit, read, agent, live, other
    }
    /// == drillID; unique per row (a tool is either loose or inside one run).
    public let id: String
    /// The timeline item id to inspect when this row is clicked.
    public let drillID: String
    public let kind: Kind
    public let title: String
    /// "done" / "+12 −13" / "3 steps" / "running" / "failed".
    public let subtitle: String
    public let isLive: Bool

    public init(drillID: String, kind: Kind, title: String,
                subtitle: String, isLive: Bool) {
        self.id = drillID
        self.drillID = drillID
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.isLive = isLive
    }
}

/// Turns a timeline (+ its subagent sub-timelines) into the Activity list.
/// Built ON TOP of `TimelineDisplay.grouped` so "what collapses into a run" is
/// defined in exactly one place (the transcript and this list never disagree).
public enum ActivityList {
    /// Names that stand for a whole subagent run, not a single tool call.
    private static let agentNames: Set<String> = ["Task", "Agent"]
    private static let editors: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]

    /// One row per unit. Order: live rows first, then everything else
    /// newest-first (both partitions stay newest-first).
    public static func rows(timeline: [TimelineItem],
                            subagents: [String: [TimelineItem]]) -> [ActivityRow] {
        var chronological: [ActivityRow] = []
        for row in TimelineDisplay.grouped(timeline) {
            switch row {
            case .toolGroup(let id, let items, let summary):
                chronological.append(groupRow(id: id, items: items, summary: summary))
            case .item(let item):
                if let row = itemRow(item, subagents: subagents) {
                    chronological.append(row)
                }
            }
        }
        let newestFirst = Array(chronological.reversed())
        return newestFirst.filter(\.isLive) + newestFirst.filter { !$0.isLive }
    }

    // MARK: - Loose items

    /// A loose timeline item → a row, or nil for anything that isn't a tool
    /// call (assistant text, thinking, user turns, permission notes, …).
    private static func itemRow(_ item: TimelineItem,
                                subagents: [String: [TimelineItem]]) -> ActivityRow? {
        guard case .toolCall(let id, let name, let summary, let input,
                             _, let isError, let isRunning) = item else {
            return nil
        }
        let label = title(summary: summary, name: name)
        // A subagent Task/Agent stays an agent row even once finished — its
        // identity (a whole sub-run with a step count) beats the generic
        // tool/live shape, so this precedes the isRunning check. While it is
        // still running it also reports live, so it floats to the top with a
        // pulse WITHOUT losing its agent shape (accent icon, step count, drill).
        if agentNames.contains(name) {
            let steps = subagents[id]?.count ?? 0
            return ActivityRow(drillID: id, kind: .agent, title: label,
                               subtitle: steps == 1 ? "1 step" : "\(steps) steps",
                               isLive: isRunning)
        }
        if isRunning {
            return ActivityRow(drillID: id, kind: .live, title: label,
                               subtitle: "running", isLive: true)
        }
        return ActivityRow(drillID: id, kind: kind(forToolName: name), title: label,
                           subtitle: subtitle(name: name, input: input, isError: isError),
                           isLive: false)
    }

    // MARK: - Collapsed runs

    /// A collapsed run of ≥3 finished tools → one summary row. `id` is the
    /// run's first tool id (a real inspectable item), matching the transcript.
    private static func groupRow(id: String, items: [TimelineItem],
                                 summary: String) -> ActivityRow {
        ActivityRow(drillID: id, kind: kind(forGroup: items), title: summary,
                    subtitle: "done", isLive: false)
    }

    // MARK: - Helpers

    /// Prefer the per-tool summary line (a command, a path, an agent brief);
    /// fall back to the tool name when the summary is empty or just echoes it.
    private static func title(summary: String, name: String) -> String {
        (summary.isEmpty || summary == name) ? name : summary
    }

    /// Finished single-tool subtitle: an edit shows its `+N −N`, an errored
    /// call reads "failed", everything else "done".
    private static func subtitle(name: String, input: JSONValue,
                                 isError: Bool?) -> String {
        if isError == true { return "failed" }
        if let diff = ToolDiff.from(toolName: name, input: input) {
            return "+\(diff.added) \u{2212}\(diff.removed)"   // U+2212, matches DiffCountChips
        }
        return "done"
    }

    private static func kind(forToolName name: String) -> ActivityRow.Kind {
        if name == "Bash" { return .command }
        if editors.contains(name) { return .edit }
        if name == "Read" { return .read }
        return .other
    }

    /// A run's kind is its tools' shared family, else `.other` (a mixed run).
    /// Absorbed interstitials (thinking / resolved-allow) are ignored.
    private static func kind(forGroup items: [TimelineItem]) -> ActivityRow.Kind {
        let kinds = Set(items.compactMap { item -> ActivityRow.Kind? in
            guard case .toolCall(_, let name, _, _, _, _, _) = item else { return nil }
            return kind(forToolName: name)
        })
        return kinds.count == 1 ? kinds.first! : .other
    }
}
