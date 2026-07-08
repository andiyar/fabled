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
        XCTAssertTrue(written.contains(#""content":"ping""#))
        let lines = written.split(separator: "\n")
        XCTAssertTrue(lines[0].contains("initialize"),
                      "initialize must precede user messages")
    }
}
