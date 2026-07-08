import XCTest
@testable import ClaudeKit

final class AgentSessionTests: XCTestCase {
    /// Writes a fake `claude` that: prints an init line, echoes every stdin
    /// line to a capture file, then prints a result line and exits.
    private func makeFakeCLI() throws -> (executable: URL, capture: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let capture = dir.appendingPathComponent("stdin-capture.jsonl")
        let script = dir.appendingPathComponent("claude")
        let initLine = String(data: Fixtures.initLine, encoding: .utf8)!
        let body = """
        #!/bin/bash
        echo '\(initLine)'
        while IFS= read -r line; do
          echo "$line" >> '\(capture.path)'
          if [[ "$line" == *'"type":"user"'* ]]; then
            echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"pong"}]},"session_id":"s1"}'
            for i in $(seq 1 2000); do echo '{"type":"system","subtype":"filler"}'; done
            echo '{"type":"result","subtype":"success","is_error":false,"session_id":"s1"}'
            exit 0
          fi
        done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, capture)
    }

    func testSessionLifecycle() async throws {
        let (fake, capture) = try makeFakeCLI()
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = fake

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("ping")

        var sawInit = false
        var texts: [String] = []
        var terminated = false
        var order: [String] = []
        for await event in await session.events {
            switch event {
            case .systemInit:
                sawInit = true
                order.append("init")
            case .assistant(let msg):
                order.append("assistant")
                for case .text(let t) in msg.content { texts.append(t) }
            case .result:
                order.append("result")
            case .terminated:
                terminated = true
                order.append("terminated")
            default:
                order.append("other")
            }
        }
        XCTAssertTrue(sawInit)
        XCTAssertEqual(texts, ["pong"])
        XCTAssertTrue(terminated)
        XCTAssertEqual(Array(order.suffix(2)), ["result", "terminated"],
                       "final events buffered at exit must not be dropped")

        let written = try String(contentsOf: capture, encoding: .utf8)
        XCTAssertTrue(written.contains(#""subtype":"initialize""#),
                      "handshake must be sent first")
        XCTAssertTrue(written.contains(#""request_id":"init""#),
                      "handshake must use the well-known initialize id")
        XCTAssertTrue(written.contains(#""content":"ping""#))
        let lines = written.split(separator: "\n")
        XCTAssertTrue(lines[0].contains("initialize"),
                      "initialize must precede user messages")
    }

    private func makePermissionFakeCLI() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        let body = """
        #!/bin/bash
        echo '{"type":"control_request","request_id":"perm-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}'
        while IFS= read -r line; do
          if [[ "$line" == *'"request_id":"perm-1"'* && "$line" == *'"behavior":"allow"'* ]]; then
            echo '{"type":"result","subtype":"success","is_error":false,"session_id":"s1"}'
            exit 0
          fi
        done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    func testPermissionRoundTrip() async throws {
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = try makePermissionFakeCLI()

        let session = AgentSession(configuration: config)
        try await session.start()

        var gotResult = false
        for await event in await session.events {
            switch event {
            case .controlRequest(let req):
                if let perm = PermissionRequest(req) {
                    XCTAssertEqual(perm.toolName, "Bash")
                    await session.respond(
                        to: perm, decision: .allow(updatedInput: perm.input))
                }
            case .result: gotResult = true
            default: break
            }
        }
        XCTAssertTrue(gotResult,
            "fake CLI only emits result if it received a well-formed allow response")
    }

    func testControlOpsReturnCorrelatableRequestIDs() async throws {
        let session = AgentSession(configuration: SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory))
        // No start() needed: write() no-ops without a pipe, ids are minted regardless.
        let modelID = await session.setModel("sonnet")
        let permissionID = await session.setPermissionMode("plan")
        let interruptID = await session.interrupt()
        XCTAssertFalse(modelID.isEmpty)
        XCTAssertEqual(Set([modelID, permissionID, interruptID]).count, 3,
                       "every control op must mint a unique id")
        XCTAssertEqual(AgentSession.initializeRequestID, "init",
                       "initialize id is a known constant so ChatSession can correlate the catalog response")
    }

    func testAgentEventIsEquatable() throws {
        let a = try AgentEventDecoder.decode(Fixtures.initLine)
        let b = try AgentEventDecoder.decode(Fixtures.initLine)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, AgentEvent.terminated(exitCode: 0))
    }

    /// A slow child that records SIGTERM to a marker file — deterministic
    /// evidence of `deinit` termination without depending on process reaping.
    /// It also writes a `ready` marker *after* installing the trap, so the test
    /// can drop the session only once the trap is armed (otherwise SIGTERM can
    /// race bash startup, hit the default disposition, and never run the trap).
    private func makeSlowChild() throws -> (executable: URL, marker: URL, ready: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent("terminated.marker")
        let ready = dir.appendingPathComponent("ready.marker")
        let script = dir.appendingPathComponent("claude")
        let body = """
        #!/bin/bash
        trap 'echo terminated > '\(marker.path)'; exit 0' TERM
        echo ready > '\(ready.path)'
        while true; do sleep 0.1; done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, marker, ready)
    }

    func testDeallocTerminatesChildAndFinishesStream() async throws {
        let (fake, marker, ready) = try makeSlowChild()
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = fake

        var session: AgentSession? = AgentSession(configuration: config)
        try await session!.start()
        let events = await session!.events

        // Wait until the child has armed its SIGTERM trap so the drop below
        // deterministically exercises the trap instead of racing bash startup.
        let readyDeadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: ready.path),
              ContinuousClock.now < readyDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path),
                      "child must arm its trap before we drop the session")

        session = nil  // drop the only reference while the child runs

        // 1. The child receives SIGTERM.
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: marker.path),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path),
                      "deinit must terminate the child process")

        // 2. The events stream finishes instead of hanging its consumer.
        let consumer = Task { for await _ in events {} }
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask { _ = await consumer.value; return true }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
            let first = await group.next()!
            group.cancelAll()
            return first
        }
        XCTAssertTrue(finished, "events stream must finish when the session deallocates")
    }

    func testSendAfterTerminationIsSafe() async throws {
        // Child exits immediately after init; writes after .terminated must be
        // short-circuited. Before the fix this test can crash the whole test
        // runner with SIGPIPE — that crash IS the failure signal.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        let initLine = String(data: Fixtures.initLine, encoding: .utf8)!
        try "#!/bin/bash\necho '\(initLine)'\nexit 0\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)

        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = script
        let session = AgentSession(configuration: config)
        try await session.start()
        for await event in await session.events {
            if case .terminated = event { break }
        }
        await session.send("into the void")   // must not write to the dead pipe
        await session.interrupt()             // ditto for control ops
    }
}
