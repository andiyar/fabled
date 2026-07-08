import Foundation
import XCTest
import ClaudeKit
@testable import FabledCore

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

/// Records everything a ChatSession sends outward.
actor OutboundRecorder {
    enum Entry: Equatable {
        case send(String)
        case respond(requestID: String, behavior: String)
        case interrupt
        case setModel(String)
        case setPermissionMode(String)
        case terminate
    }
    private(set) var entries: [Entry] = []
    func record(_ entry: Entry) { entries.append(entry) }
}

func makeFakeConnection()
    -> (AgentConnection, AsyncStream<AgentEvent>.Continuation, OutboundRecorder) {
    let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
    let recorder = OutboundRecorder()
    let connection = AgentConnection(
        events: { stream },
        send: { await recorder.record(.send($0)) },
        respond: { request, decision in
            let behavior = if case .allow = decision { "allow" } else { "deny" }
            await recorder.record(.respond(requestID: request.requestID, behavior: behavior))
        },
        interrupt: { await recorder.record(.interrupt) },
        setModel: { await recorder.record(.setModel($0)) },
        setPermissionMode: { await recorder.record(.setPermissionMode($0)) },
        terminate: { await recorder.record(.terminate) })
    return (connection, continuation, recorder)
}

enum CorpusBuilder {
    /// A temp ~/.claude/projects-shaped tree built from the transcript
    /// fixtures, with staggered mtimes (tooluse newest … titled oldest).
    static func make() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-\(UUID().uuidString)")
        let project = root.appendingPathComponent("-tmp-fabled-demo")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fixtures = [
            ("real-titled-session", "97c70bda-ac5d-4e12-982e-8e6e35dd2674", -3.0),
            ("real-untitled-session", "036b246d-0898-4ace-89b2-8fdd6c107fc4", -2.0),
            ("real-tooluse-session", "21feb0f8-e41a-4f72-9efb-9232b5bb64de", -1.0),
        ]
        for (fixture, sessionID, minutesAgo) in fixtures {
            let destination = project.appendingPathComponent("\(sessionID).jsonl")
            try FileManager.default.copyItem(
                at: CoreFixtures.fixturesDir
                    .appendingPathComponent("transcripts/\(fixture).jsonl"),
                to: destination)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: minutesAgo * 60)],
                ofItemAtPath: destination.path)
        }
        return root
    }
}

/// Polls a MainActor condition until it holds or the test fails.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ what: String = "condition",
    _ condition: () -> Bool
) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        if clock.now > deadline {
            return XCTFail("timed out waiting for \(what)")
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Outbound calls hop through a Task — wait for the recorder to catch up.
func waitForEntries(
    _ recorder: OutboundRecorder, count: Int, timeout: Duration = .seconds(2)
) async -> [OutboundRecorder.Entry] {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        let entries = await recorder.entries
        if entries.count >= count { return entries }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await recorder.entries
}
