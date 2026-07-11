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
        var run: [TimelineItem] = []

        func flush() {
            if run.count >= minimumRun, let first = run.first {
                rows.append(.toolGroup(id: first.id, items: run,
                                       summary: summary(for: run)))
            } else {
                rows += run.map(TimelineRow.item)
            }
            run = []
        }

        for item in items {
            if case .toolCall(_, let name, _, _, _, let isError, let isRunning) = item,
               !isRunning, isError != true, !anchors.contains(name) {
                run.append(item)
            } else {
                flush()
                rows.append(.item(item))
            }
        }
        flush()
        return rows
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
