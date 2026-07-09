import XCTest
@testable import ClaudeKit

final class SessionConfigurationTests: XCTestCase {
    /// Writes an executable `claude` at `<dir>/claude`, creating `dir` first.
    private func makeFakeClaude(in dir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let exe = dir.appendingPathComponent("claude")
        try Data("#!/bin/sh\n".utf8).write(to: exe)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    }

    func testResolverFindsHomeLocalBin() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try makeFakeClaude(in: home.appendingPathComponent(".local/bin"))
        defer { try? FileManager.default.removeItem(at: home) }

        let resolved = SessionConfiguration.resolveClaudeExecutable(
            environmentPATH: nil, home: home)
        XCTAssertEqual(resolved?.path, home.appendingPathComponent(".local/bin/claude").path)
    }

    func testResolverPrefersPATHOverHome() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        let pathDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        try makeFakeClaude(in: home.appendingPathComponent(".local/bin"))
        try makeFakeClaude(in: pathDir)
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: pathDir)
        }

        let resolved = SessionConfiguration.resolveClaudeExecutable(
            environmentPATH: pathDir.path, home: home)
        XCTAssertEqual(resolved?.path, pathDir.appendingPathComponent("claude").path,
                       "a PATH hit wins over the home install locations")
    }

    func testResolverReturnsNilWhenNothingFound() {
        let emptyHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
        XCTAssertNil(SessionConfiguration.resolveClaudeExecutable(
            environmentPATH: nil, home: emptyHome))
    }

    /// Depends on a local install (~/.local/bin/claude) — the real-world repro
    /// of the GUI PATH bug. Gated on the file existing so it stays CI-safe.
    func testResolverFindsRealLocalInstall() throws {
        let realHome = FileManager.default.homeDirectoryForCurrentUser
        let localClaude = realHome.appendingPathComponent(".local/bin/claude")
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: localClaude.path),
                          "no ~/.local/bin/claude on this machine")
        XCTAssertNotNil(SessionConfiguration.resolveClaudeExecutable(
            environmentPATH: nil, home: realHome),
            "minimal PATH must still resolve the local install")
    }

    func testBaseArguments() {
        let config = SessionConfiguration(
            workingDirectory: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(config.arguments(), [
            "-p", "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-prompt-tool", "stdio",
            "--include-partial-messages",
        ])
    }

    func testIncludePartialMessagesFlag() {
        var config = SessionConfiguration(workingDirectory: URL(fileURLWithPath: "/tmp"))
        XCTAssertTrue(config.arguments().contains("--include-partial-messages"),
                      "streaming deltas are on by default — Fabled always wants them")
        config.includePartialMessages = false
        XCTAssertFalse(config.arguments().contains("--include-partial-messages"))
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
