import ClaudeKit

/// One-line summaries for collapsed tool cards.
enum ToolCallSummary {
    static func summarize(name: String, input: JSONValue) -> String {
        let detail: String? = switch name {
        case "Bash": input["command"]?.stringValue
        case "Read", "Write", "Edit", "NotebookEdit": input["file_path"]?.stringValue
        case "Glob", "Grep": input["pattern"]?.stringValue
        case "WebFetch": input["url"]?.stringValue
        case "WebSearch": input["query"]?.stringValue
        case "Task", "Agent": input["description"]?.stringValue
        case "AskUserQuestion":
            input["questions"]?.arrayValue?.first?["question"]?.stringValue
        case "ExitPlanMode": input["plan"]?.stringValue
        case "TodoWrite": todoSummary(input)
        default: nil
        }
        guard let detail, !detail.isEmpty else { return name }
        let firstLine = detail.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? detail
        return String(firstLine.prefix(120))
    }

    private static func todoSummary(_ input: JSONValue) -> String? {
        let todos = TodoItem.list(from: input)
        guard !todos.isEmpty else { return nil }
        let done = todos.count { $0.status == .completed }
        return "\(done)/\(todos.count) done"
    }
}
