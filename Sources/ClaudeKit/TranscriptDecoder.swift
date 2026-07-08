import Foundation

public enum TranscriptDecoder {
    /// Session-metadata line types observed across the full on-disk corpus
    /// (2026-07-08 census). New CLI line types deliberately fall through to
    /// `.unknown` instead — that is the protocol-drift insurance working.
    static let sessionMetaTypes: Set<String> = [
        "mode", "permission-mode", "last-prompt", "file-history-snapshot",
        "agent-name", "started", "worktree-state", "frame-link",
    ]

    /// Decodes one transcript line. Throws only when the line is not JSON;
    /// every well-formed JSON object decodes to some entry.
    public static func decode(_ line: Data) throws -> TranscriptEntry {
        let raw = try JSONValue(parsing: line)
        let type = raw["type"]?.stringValue ?? ""
        switch type {
        case "user":
            return decodeUser(raw)
        case "assistant", "system":
            return .event(AgentEventDecoder.decode(raw: raw), context: LineContext(raw: raw))
        case "custom-title":
            return .title(text: raw["customTitle"]?.stringValue ?? "", isCustom: true, raw: raw)
        case "ai-title":
            return .title(text: raw["aiTitle"]?.stringValue ?? "", isCustom: false, raw: raw)
        case "summary":
            return .summary(text: raw["summary"]?.stringValue ?? "", raw: raw)
        case "queue-operation":
            return .queueOperation(
                operation: raw["operation"]?.stringValue ?? "",
                content: raw["content"]?.stringValue,
                raw: raw)
        case "attachment":
            return .attachment(raw: raw)
        case "result" where raw["key"] != nil:
            // On-disk `result` lines are subagent result caches (key +
            // agentId), NOT turn results — never route them through
            // AgentEventDecoder, which would fabricate a TurnResult.
            return .sessionMeta(type: type, raw: raw)
        case let known where sessionMetaTypes.contains(known):
            return .sessionMeta(type: type, raw: raw)
        default:
            return .unknown(raw: raw)
        }
    }

    private static func decodeUser(_ raw: JSONValue) -> TranscriptEntry {
        let context = LineContext(raw: raw)
        let content = raw["message"]?["content"]
        if let text = content?.stringValue {
            return .userPrompt(text: text, context: context, raw: raw)
        }
        let blocks = content?.arrayValue ?? []
        let hasToolResult = blocks.contains { $0["type"]?.stringValue == "tool_result" }
        if hasToolResult {
            return .event(AgentEventDecoder.decode(raw: raw), context: context)
        }
        let text = blocks
            .compactMap { block -> String? in
                guard block["type"]?.stringValue == "text" else { return nil }
                return block["text"]?.stringValue
            }
            .joined(separator: "\n")
        return .userPrompt(text: text, context: context, raw: raw)
    }
}
