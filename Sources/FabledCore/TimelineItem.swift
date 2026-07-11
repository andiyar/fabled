import ClaudeKit

/// The UI vocabulary: everything the conversation view renders. Views never
/// pattern-match raw AgentEvents — TimelineReducer is the only translator.
/// This shape is the locked contract from the Plan 3 brief.
public enum TimelineItem: Sendable, Identifiable, Equatable {
    case userMessage(id: String, text: String)
    case assistantText(id: String, markdown: String, isStreaming: Bool)
    case thinking(id: String, text: String, isStreaming: Bool)
    case toolCall(id: String, name: String, summary: String,
                  input: JSONValue, result: JSONValue?, isError: Bool?, isRunning: Bool)
    case permission(id: String, request: PermissionRequest,
                    resolution: PermissionDecision?)
    case turnSummary(id: String, result: TurnResult)
    case notice(id: String, text: String)
    case raw(id: String, type: String, raw: JSONValue)

    public var id: String {
        switch self {
        case .userMessage(let id, _),
             .assistantText(let id, _, _),
             .thinking(let id, _, _),
             .toolCall(let id, _, _, _, _, _, _),
             .permission(let id, _, _),
             .turnSummary(let id, _),
             .notice(let id, _),
             .raw(let id, _, _):
            return id
        }
    }

    /// Non-nil for tool calls — the reducer's result-matching key.
    var toolCallID: String? {
        if case .toolCall(let id, _, _, _, _, _, _) = self { return id }
        return nil
    }
}
