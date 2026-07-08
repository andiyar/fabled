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
    case controlRequest(ControlRequest)
    case controlResponse(ControlResponseEnvelope)
    case unknown(type: String, raw: JSONValue)
    case terminated(exitCode: Int32)
}

public struct ControlRequest: Sendable, Equatable {
    public let requestID: String
    public let subtype: String
    public let payload: JSONValue
}

public struct ControlResponseEnvelope: Sendable, Equatable {
    public let requestID: String
    public let subtype: String
    public let payload: JSONValue?
}

public struct PermissionRequest: Sendable, Equatable {
    public let requestID: String
    public let toolName: String
    public let displayName: String?
    public let input: JSONValue
    public let description: String?
    public let decisionReason: String?
    public let suggestions: [JSONValue]

    public init?(_ request: ControlRequest) {
        guard request.subtype == "can_use_tool",
              let toolName = request.payload["tool_name"]?.stringValue else { return nil }
        self.requestID = request.requestID
        self.toolName = toolName
        self.displayName = request.payload["display_name"]?.stringValue
        self.input = request.payload["input"] ?? .null
        self.description = request.payload["description"]?.stringValue
        self.decisionReason = request.payload["decision_reason"]?.stringValue
        self.suggestions = request.payload["permission_suggestions"]?.arrayValue ?? []
    }
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
