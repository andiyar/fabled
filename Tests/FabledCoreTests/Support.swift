import Foundation
import ClaudeKit

enum CoreFixtures {
    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // FabledCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("fixtures")
    }

    static func lines(_ name: String) throws -> [Data] {
        let text = try String(contentsOf: fixturesDir.appendingPathComponent(name),
                              encoding: .utf8)
        return text.split(separator: "\n").map { Data($0.utf8) }
    }

    /// Live-stream fixture → events.
    static func events(_ name: String) throws -> [AgentEvent] {
        try lines(name).map { try AgentEventDecoder.decode($0) }
    }

    /// On-disk transcript fixture → entries.
    static func transcript(_ name: String) throws -> [TranscriptEntry] {
        try lines("transcripts/\(name)").map { try TranscriptDecoder.decode($0) }
    }
}
