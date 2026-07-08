import Foundation

/// Wrapper metadata carried by message lines (user/assistant/system) in
/// on-disk session files. Absent fields default to false/nil — many line
/// types carry none of this.
public struct LineContext: Sendable, Equatable {
    public let uuid: String?
    public let parentUUID: String?
    public let timestamp: Date?
    public let isSidechain: Bool
    public let isMeta: Bool
    public let isCompactSummary: Bool
    public let agentID: String?

    public init(raw: JSONValue) {
        self.uuid = raw["uuid"]?.stringValue
        self.parentUUID = raw["parentUuid"]?.stringValue
        self.timestamp = raw["timestamp"]?.stringValue.flatMap(Self.parseTimestamp)
        self.isSidechain = raw["isSidechain"]?.boolValue ?? false
        self.isMeta = raw["isMeta"]?.boolValue ?? false
        self.isCompactSummary = raw["isCompactSummary"]?.boolValue ?? false
        self.agentID = raw["agentId"]?.stringValue
    }

    /// Transcript timestamps are ISO8601, usually with fractional seconds
    /// ("2026-06-12T22:59:49.641Z") but occasionally without.
    static func parseTimestamp(_ string: String) -> Date? {
        (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(string, strategy: Date.ISO8601FormatStyle()))
    }
}

/// One line of an on-disk session transcript. The on-disk format is a
/// superset of the live stream: it interleaves conversation events with
/// titles, queue bookkeeping, and session metadata.
public enum TranscriptEntry: Sendable {
    /// A human-typed prompt: `user` line whose content is a string or a
    /// block array without tool results.
    case userPrompt(text: String, context: LineContext, raw: JSONValue)
    /// Anything Plan 1's AgentEventDecoder understands: assistant turns,
    /// tool results, system events.
    case event(AgentEvent, context: LineContext)
    /// `custom-title` (user-set, isCustom: true) or `ai-title` lines.
    /// Later occurrences override earlier ones.
    case title(text: String, isCustom: Bool, raw: JSONValue)
    /// Legacy `summary` lines. None exist in the 2026-07 corpus; kept for
    /// older session files.
    case summary(text: String, raw: JSONValue)
    case queueOperation(operation: String, content: String?, raw: JSONValue)
    case attachment(raw: JSONValue)
    /// Known bookkeeping line types (mode, last-prompt, file-history-snapshot,
    /// subagent result caches, ...). Typed loosely on purpose.
    case sessionMeta(type: String, raw: JSONValue)
    case unknown(raw: JSONValue)
}
