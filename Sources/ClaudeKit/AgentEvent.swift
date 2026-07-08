public struct SystemInit: Sendable, Equatable {
    public let sessionID: String
    public let model: String
    public let cwd: String
    public let tools: [String]
    public let permissionMode: String
    public let slashCommands: [String]
    public let agents: [String]
    public let skills: [String]
    public let cliVersion: String
    public let raw: JSONValue
}

public enum AgentEvent: Sendable {
    case systemInit(SystemInit)
    case system(subtype: String, raw: JSONValue)
    case assistant(AssistantMessage)
    case toolResult([ToolResult])
    case result(TurnResult)
    case unknown(type: String, raw: JSONValue)
}

public enum ContentBlock: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case unknown(type: String, raw: JSONValue)
}

public struct AssistantMessage: Sendable, Equatable {
    public let content: [ContentBlock]
    public let model: String?
    public let sessionID: String?
    public let parentToolUseID: String?
    public let raw: JSONValue
}

public struct ToolResult: Sendable, Equatable {
    public let toolUseID: String
    public let content: JSONValue
    public let isError: Bool
}

public struct TurnResult: Sendable, Equatable {
    public let subtype: String
    public let isError: Bool
    public let durationMS: Double?
    public let totalCostUSD: Double?
    public let usage: JSONValue?
    public let permissionDenials: [JSONValue]
    public let raw: JSONValue
}
