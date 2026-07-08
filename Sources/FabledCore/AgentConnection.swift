import ClaudeKit
import Foundation

/// The transport a ChatSession talks through. Injected so view-model
/// behavior is fully testable; `live(_:)` wraps the real AgentSession.
public struct AgentConnection: Sendable {
    public var events: @Sendable () async -> AsyncStream<AgentEvent>
    public var send: @Sendable (String) async -> Void
    public var respond: @Sendable (PermissionRequest, PermissionDecision) async -> Void
    public var interrupt: @Sendable () async -> Void
    public var setModel: @Sendable (String) async -> Void
    public var setPermissionMode: @Sendable (String) async -> Void
    public var terminate: @Sendable () async -> Void

    public init(
        events: @escaping @Sendable () async -> AsyncStream<AgentEvent>,
        send: @escaping @Sendable (String) async -> Void,
        respond: @escaping @Sendable (PermissionRequest, PermissionDecision) async -> Void,
        interrupt: @escaping @Sendable () async -> Void,
        setModel: @escaping @Sendable (String) async -> Void,
        setPermissionMode: @escaping @Sendable (String) async -> Void,
        terminate: @escaping @Sendable () async -> Void
    ) {
        self.events = events
        self.send = send
        self.respond = respond
        self.interrupt = interrupt
        self.setModel = setModel
        self.setPermissionMode = setPermissionMode
        self.terminate = terminate
    }

    public static func live(_ session: AgentSession) -> AgentConnection {
        AgentConnection(
            events: { await session.events },
            send: { await session.send($0) },
            respond: { await session.respond(to: $0, decision: $1) },
            interrupt: { _ = await session.interrupt() },
            setModel: { _ = await session.setModel($0) },
            setPermissionMode: { _ = await session.setPermissionMode($0) },
            terminate: { await session.terminate() })
    }
}

/// One entry of the initialize response's slash-command catalog.
public struct SlashCommand: Sendable, Equatable, Identifiable {
    public let name: String
    public let commandDescription: String
    public let argumentHint: String
    public var id: String { name }

    public init(name: String, commandDescription: String, argumentHint: String) {
        self.name = name
        self.commandDescription = commandDescription
        self.argumentHint = argumentHint
    }
}

/// One entry of the initialize response's model catalog (probe finding 9).
public struct ModelOption: Sendable, Equatable, Identifiable {
    public let value: String
    public let resolvedModel: String?
    public let displayName: String
    public let optionDescription: String?
    public var id: String { value }

    public init(value: String, resolvedModel: String?,
                displayName: String, optionDescription: String?) {
        self.value = value
        self.resolvedModel = resolvedModel
        self.displayName = displayName
        self.optionDescription = optionDescription
    }
}
