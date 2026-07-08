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
        default: nil
        }
        guard let detail, !detail.isEmpty else { return name }
        let firstLine = detail.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? detail
        return String(firstLine.prefix(120))
    }
}
