import Foundation

public enum AgentEventDecoder {
    public static func decode(_ line: Data) throws -> AgentEvent {
        let raw = try JSONDecoder().decode(JSONValue.self, from: line)
        let type = raw["type"]?.stringValue ?? ""
        switch type {
        case "system":
            let subtype = raw["subtype"]?.stringValue ?? ""
            if subtype == "init" { return .systemInit(Self.systemInit(from: raw)) }
            return .system(subtype: subtype, raw: raw)
        default:
            return .unknown(type: type, raw: raw)
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
