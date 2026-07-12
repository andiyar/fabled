import Foundation

/// One rendered transcript row: a plain item, or a collapsed run of tool
/// calls (CD digest §2a). Pure presentation pass — the reducer's output is
/// untouched, so the inspector/id vocabulary is unchanged.
public enum TimelineRow: Identifiable, Equatable, Sendable {
    case item(TimelineItem)
    case toolGroup(id: String, items: [TimelineItem], summary: String)

    public var id: String {
        switch self {
        case .item(let item): item.id
        case .toolGroup(let id, _, _): "group-\(id)"
        }
    }
}

public enum TimelineDisplay {
    /// Names whose rows carry their own affordances and must stay visible.
    private static let anchors: Set<String> = ["Task", "Agent"]
    /// Minimum run length worth collapsing.
    private static let minimumRun = 3

    public static func grouped(_ items: [TimelineItem]) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        var run: [TimelineItem] = []     // groupable tool calls + absorbed interstitials, in order
        var toolCount = 0                // count of groupable tool calls currently in `run`
        var pending: [TimelineItem] = [] // transparent items seen since the last tool call

        func flush() {
            if toolCount >= minimumRun, let first = run.first(where: { $0.toolCallID != nil }) {
                rows.append(.toolGroup(id: first.id, items: run, summary: summary(for: run)))
            } else {
                rows += run.map(TimelineRow.item)
            }
            rows += pending.map(TimelineRow.item)   // leftover transparents render loose, in order
            run = []; toolCount = 0; pending = []
        }

        for item in items {
            if isGroupable(item) {
                run += pending; pending = []        // transparents before this tool join the run
                run.append(item); toolCount += 1
            } else if isTransparent(item) {
                pending.append(item)                // always hold; absorbed if a tool follows, else flushed loose
            } else {
                flush()
                rows.append(.item(item))            // hard break renders on its own
            }
        }
        flush()
        return rows
    }

    private static func isGroupable(_ item: TimelineItem) -> Bool {
        if case .toolCall(_, let name, _, _, _, let isError, let isRunning) = item {
            return !isRunning && isError != true && !anchors.contains(name)
        }
        return false
    }

    private static func isTransparent(_ item: TimelineItem) -> Bool {
        switch item {
        case .thinking:
            return true
        case .permission(_, _, .some(.allow)):   // resolved-allow is noise once decided
            return true                          // .deny / nil (pending) / everything else = hard break
        default:
            return false
        }
    }

    private static func summary(for run: [TimelineItem]) -> String {
        let names: [String] = run.compactMap {
            if case .toolCall(_, let name, _, _, _, _, _) = $0 { return name }
            return nil
        }
        let unique = Set(names)
        let editors: Set<String> = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
        if unique == ["Bash"] { return "Ran \(names.count) commands" }
        if unique.isSubset(of: editors) { return "Edited \(names.count) files" }
        if unique.count == 1, let name = unique.first {
            return "\(names.count) × \(name)"
        }
        return "\(names.count) steps"
    }
}
