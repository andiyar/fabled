import ClaudeKit

/// Text the permission card shows, derived from the CLI's request payload.
public enum PermissionPrompt {
    /// "Always allow: Bash(git init *)" — from the first addRules suggestion.
    /// nil when the CLI offered no rules (the button is hidden).
    public static func alwaysAllowLabel(for suggestions: [JSONValue]) -> String? {
        for suggestion in suggestions
        where suggestion["type"]?.stringValue == "addRules" {
            let rules = (suggestion["rules"]?.arrayValue ?? []).compactMap { rule -> String? in
                guard let tool = rule["toolName"]?.stringValue else { return nil }
                guard let content = rule["ruleContent"]?.stringValue, !content.isEmpty else {
                    return tool
                }
                return "\(tool)(\(content))"
            }
            if !rules.isEmpty {
                return "Always allow: " + rules.joined(separator: ", ")
            }
        }
        return nil
    }

    /// What is being approved, one line: Bash commands verbatim, other
    /// tools by their summarized input.
    public static func commandSummary(for request: PermissionRequest) -> String {
        request.input["command"]?.stringValue
            ?? ToolCallSummary.summarize(name: request.toolName, input: request.input)
    }
}
