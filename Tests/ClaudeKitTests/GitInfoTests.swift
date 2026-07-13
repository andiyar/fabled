import XCTest
@testable import ClaudeKit

final class GitInfoTests: XCTestCase {

    /// Runs a real `git` in `dir`, throwing on a nonzero exit. stdout/stderr
    /// are discarded — these calls are setup, not the thing under test.
    @discardableResult
    private func git(_ args: [String], in dir: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let status = process.terminationStatus
        if status != 0 {
            throw NSError(domain: "git", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "git \(args.joined(separator: " ")) exited \(status)"])
        }
        return status
    }

    func testReadsBranchAndDiffFromARepo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try git(["init", "-q"], in: dir)
        try git(["config", "user.email", "t@t"], in: dir)
        try git(["config", "user.name", "t"], in: dir)
        try "hello\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: dir)
        try git(["commit", "-qm", "init"], in: dir)
        // Modify the tracked file (unstaged) so `git diff --numstat` reports +1.
        try "hello\nworld\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let info = try await GitInfo.read(at: dir)
        XCTAssertNotNil(info)
        XCTAssertTrue(info?.branch == "main" || info?.branch == "master",
                      "branch was \(String(describing: info?.branch))")
        XCTAssertGreaterThanOrEqual(info?.added ?? 0, 1)
    }

    func testNonRepoReturnsNil() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let info = try await GitInfo.read(at: dir)
        XCTAssertNil(info)
    }

    /// After staging a modified tracked file, the diff must STILL count its
    /// changed lines. `git diff --numstat` (no ref) silently drops staged
    /// changes to 0; `git diff HEAD --numstat` counts staged AND unstaged.
    func testCountsStagedChangesToTrackedFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try git(["init", "-q"], in: dir)
        try git(["config", "user.email", "t@t"], in: dir)
        try git(["config", "user.name", "t"], in: dir)
        try "hello\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: dir)
        try git(["commit", "-qm", "init"], in: dir)
        // Modify AND stage the change — the old `git diff --numstat` reports 0.
        try "hello\nworld\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "a.txt"], in: dir)

        let info = try await GitInfo.read(at: dir)
        XCTAssertNotNil(info)
        XCTAssertGreaterThanOrEqual(info?.added ?? 0, 1,
                                    "staged changes to a tracked file must still count")
    }

    /// A repo with no commits has an unborn HEAD: `git rev-parse --abbrev-ref
    /// HEAD` exits non-zero, so read returns nil (never crashes/hangs) even
    /// though `git diff HEAD` would also fail.
    func testNoCommitsRepoReturnsNil() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try git(["init", "-q"], in: dir)
        try git(["config", "user.email", "t@t"], in: dir)
        try git(["config", "user.name", "t"], in: dir)
        // No commit → unborn HEAD.

        let info = try await GitInfo.read(at: dir)
        XCTAssertNil(info)
    }

    /// The repo name is the working tree's last path component (from
    /// `git rev-parse --show-toplevel`).
    func testReportsRepoNameFromToplevel() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try git(["init", "-q"], in: dir)
        try git(["config", "user.email", "t@t"], in: dir)
        try git(["config", "user.name", "t"], in: dir)
        try "hello\n".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."], in: dir)
        try git(["commit", "-qm", "init"], in: dir)

        let info = try await GitInfo.read(at: dir)
        XCTAssertNotNil(info)
        // --show-toplevel may resolve symlinks (/var → /private/var), so compare
        // the last path component, which is the UUID dir name either way.
        XCTAssertEqual(info?.repo, dir.lastPathComponent)
    }
}
