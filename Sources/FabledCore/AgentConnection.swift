import ClaudeKit
import Foundation

/// The transport a ChatSession talks through. Injected so view-model
/// behavior is fully testable; `live(_:)` wraps the real AgentSession.
public struct AgentConnection: Sendable {
    public var events: @Sendable () async -> AsyncStream<AgentEvent>
    public var send: @Sendable (String) async -> Void
    public var respond: @Sendable (PermissionRequest, PermissionDecision) async -> Void
    public var interrupt: @Sendable () async -> Void
    /// Returns the CLI request id the control op was sent under, so the
    /// caller can correlate its ack (ChatSession revert bookkeeping, T6).
    public var setModel: @Sendable (String) async -> String
    public var setPermissionMode: @Sendable (String) async -> String
    public var terminate: @Sendable () async -> Void

    public init(
        events: @escaping @Sendable () async -> AsyncStream<AgentEvent>,
        send: @escaping @Sendable (String) async -> Void,
        respond: @escaping @Sendable (PermissionRequest, PermissionDecision) async -> Void,
        interrupt: @escaping @Sendable () async -> Void,
        setModel: @escaping @Sendable (String) async -> String,
        setPermissionMode: @escaping @Sendable (String) async -> String,
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
            setModel: { await session.setModel($0) },
            setPermissionMode: { await session.setPermissionMode($0) },
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

/// One entry of the initialize response's model catalog (probe finding 9;
/// effort metadata probe finding 5, 2026-07-11).
public struct ModelOption: Sendable, Equatable, Identifiable {
    public let value: String
    public let resolvedModel: String?
    public let displayName: String
    public let optionDescription: String?
    /// Whether the model takes an effort level. Hand-maintained knownModels
    /// entries claim true with an EMPTY levels list = "unknown, offer the
    /// standard five"; only the live catalog states levels authoritatively.
    public let supportsEffort: Bool
    public let supportedEffortLevels: [String]
    public var id: String { value }

    public init(value: String, resolvedModel: String?,
                displayName: String, optionDescription: String?,
                supportsEffort: Bool = true,
                supportedEffortLevels: [String] = []) {
        self.value = value
        self.resolvedModel = resolvedModel
        self.displayName = displayName
        self.optionDescription = optionDescription
        self.supportsEffort = supportsEffort
        self.supportedEffortLevels = supportedEffortLevels
    }
}

public extension ModelOption {
    /// Manually maintained list of all currently available Claude models
    /// (Ben's explicit request, 2026-07-09): the CLI's initialize catalog
    /// only advertises a subset, so the picker merges this in. Update by
    /// hand when Anthropic ships or retires models — IDs are exact, no
    /// date suffixes.
    static let knownModels: [ModelOption] = [
        ModelOption(value: "claude-fable-5", resolvedModel: "claude-fable-5", displayName: "Claude Fable 5", optionDescription: nil),
        ModelOption(value: "claude-opus-4-8", resolvedModel: "claude-opus-4-8", displayName: "Claude Opus 4.8", optionDescription: nil),
        ModelOption(value: "claude-opus-4-7", resolvedModel: "claude-opus-4-7", displayName: "Claude Opus 4.7", optionDescription: nil),
        ModelOption(value: "claude-opus-4-6", resolvedModel: "claude-opus-4-6", displayName: "Claude Opus 4.6", optionDescription: nil),
        ModelOption(value: "claude-opus-4-5", resolvedModel: "claude-opus-4-5-20251101", displayName: "Claude Opus 4.5", optionDescription: nil),
        ModelOption(value: "claude-sonnet-5", resolvedModel: "claude-sonnet-5", displayName: "Claude Sonnet 5", optionDescription: nil),
        ModelOption(value: "claude-sonnet-4-6", resolvedModel: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6", optionDescription: nil),
        ModelOption(value: "claude-haiku-4-5", resolvedModel: "claude-haiku-4-5", displayName: "Claude Haiku 4.5", optionDescription: nil),
    ]

    /// Catalog + known models, catalog entries first and authoritative;
    /// known entries whose value OR resolved id already appears in the
    /// catalog (as a value OR resolved id, ignoring a "[1m]" long-context
    /// suffix) are dropped. Matching on both sides prevents duplicates when
    /// a known alias (e.g. `claude-opus-4-5`) and the catalog's dated id
    /// (`claude-opus-4-5-20251101`) denote the same model.
    static func merged(catalog: [ModelOption]) -> [ModelOption] {
        var seen = Set<String>()
        for option in catalog {
            seen.insert(normalize(option.value))
            if let resolved = option.resolvedModel { seen.insert(normalize(resolved)) }
        }
        return catalog + knownModels.filter { known in
            if seen.contains(normalize(known.value)) { return false }
            if let resolved = known.resolvedModel, seen.contains(normalize(resolved)) { return false }
            return true
        }
    }

    private static func normalize(_ id: String) -> String {
        id.hasSuffix("[1m]") ? String(id.dropLast(4)) : id
    }
}
