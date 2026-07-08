import XCTest
@testable import ClaudeKit

final class SessionConfigurationTests: XCTestCase {
    func testBaseArguments() {
        let config = SessionConfiguration(
            workingDirectory: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(config.arguments(), [
            "-p", "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-prompt-tool", "stdio",
        ])
    }

    func testAllOptions() {
        var config = SessionConfiguration(
            workingDirectory: URL(fileURLWithPath: "/tmp/x"))
        config.model = "claude-fable-5"
        config.resumeSessionID = "abc-123"
        config.forkSession = true
        config.permissionMode = "acceptEdits"
        let args = config.arguments()
        XCTAssertTrue(args.contains("--model"))
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "claude-fable-5")
        XCTAssertEqual(args[args.firstIndex(of: "--resume")! + 1], "abc-123")
        XCTAssertTrue(args.contains("--fork-session"))
        XCTAssertEqual(args[args.firstIndex(of: "--permission-mode")! + 1], "acceptEdits")
    }
}
