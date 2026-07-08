import Foundation

public enum AgentEventDecoder {
    public static func decode(_ line: Data) throws -> AgentEvent {
        try decode(raw: JSONDecoder().decode(JSONValue.self, from: line))
    }

    public static func decode(raw: JSONValue) -> AgentEvent {
        let type = raw["type"]?.stringValue ?? ""
        switch type {
        case "system":
            let subtype = raw["subtype"]?.stringValue ?? ""
            if subtype == "init" { return .systemInit(Self.systemInit(from: raw)) }
            return .system(subtype: subtype, raw: raw)
        case "assistant":
            let message = raw["message"]
            let blocks = (message?["content"]?.arrayValue ?? []).map(Self.contentBlock)
            return .assistant(AssistantMessage(
                content: blocks,
                model: message?["model"]?.stringValue,
                sessionID: raw["session_id"]?.stringValue,
                parentToolUseID: raw["parent_tool_use_id"]?.stringValue,
                raw: raw))
        case "user":
            let blocks = raw["message"]?["content"]?.arrayValue ?? []
            let results = blocks.compactMap { block -> ToolResult? in
                guard block["type"]?.stringValue == "tool_result",
                      let id = block["tool_use_id"]?.stringValue else { return nil }
                return ToolResult(
                    toolUseID: id,
                    content: block["content"] ?? .null,
                    isError: block["is_error"]?.boolValue ?? false)
            }
            return .toolResult(results)
        case "result":
            return .result(TurnResult(
                subtype: raw["subtype"]?.stringValue ?? "",
                isError: raw["is_error"]?.boolValue ?? false,
                durationMS: raw["duration_ms"]?.doubleValue,
                totalCostUSD: raw["total_cost_usd"]?.doubleValue,
                usage: raw["usage"],
                permissionDenials: raw["permission_denials"]?.arrayValue ?? [],
                raw: raw))
        case "rate_limit_event":
            return .system(subtype: "rate_limit_event", raw: raw)
        case "control_request":
            return .controlRequest(ControlRequest(
                requestID: raw["request_id"]?.stringValue ?? "",
                subtype: raw["request"]?["subtype"]?.stringValue ?? "",
                payload: raw["request"] ?? .null))
        case "control_response":
            let response = raw["response"]
            return .controlResponse(ControlResponseEnvelope(
                requestID: response?["request_id"]?.stringValue ?? "",
                subtype: response?["subtype"]?.stringValue ?? "",
                payload: response?["response"]))
        default:
            return .unknown(type: type, raw: raw)
        }
    }

    static func contentBlock(_ block: JSONValue) -> ContentBlock {
        switch block["type"]?.stringValue {
        case "text":
            return .text(block["text"]?.stringValue ?? "")
        case "thinking":
            return .thinking(block["thinking"]?.stringValue ?? "")
        case "tool_use":
            return .toolUse(
                id: block["id"]?.stringValue ?? "",
                name: block["name"]?.stringValue ?? "",
                input: block["input"] ?? .null)
        default:
            return .unknown(type: block["type"]?.stringValue ?? "", raw: block)
        }
    }

    static func strings(_ value: JSONValue?) -> [String] {
        value?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    static func systemInit(from raw: JSONValue) -> SystemInit {
        SystemInit(
            sessionID: raw["session_id"]?.stringValue ?? "",
            model: raw["model"]?.stringValue ?? "",
            cwd: raw["cwd"]?.stringValue ?? "",
            tools: strings(raw["tools"]),
            permissionMode: raw["permissionMode"]?.stringValue ?? "",
            slashCommands: strings(raw["slash_commands"]),
            agents: strings(raw["agents"]),
            skills: strings(raw["skills"]),
            cliVersion: raw["claude_code_version"]?.stringValue ?? "",
            raw: raw)
    }
}
