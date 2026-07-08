import XCTest
@testable import ClaudeKit

final class ProjectFolderTests: XCTestCase {

    /// Builds a fake directory-exists check from a set of real paths,
    /// mimicking FileManager: every ancestor exists, trailing "/" tolerated.
    private func existsCheck(for paths: [String]) -> (String) -> Bool {
        var directories: Set<String> = ["/"]
        for path in paths {
            var url = URL(fileURLWithPath: path)
            while url.path != "/" {
                directories.insert(url.path)
                url = url.deletingLastPathComponent()
            }
        }
        return { candidate in
            let normalized = candidate.count > 1 && candidate.hasSuffix("/")
                ? String(candidate.dropLast()) : candidate
            return directories.contains(normalized)
        }
    }

    func testSimpleAllSlashPath() {
        let exists = existsCheck(for: ["/Users/andiyar/Developer/Wine"])
        XCTAssertEqual(
            PathDeflattener.originalPath(for: "-Users-andiyar-Developer-Wine", directoryExists: exists),
            "/Users/andiyar/Developer/Wine")
    }

    func testDoubleDashResolvesToDotDirectory() {
        let exists = existsCheck(for: ["/Users/andiyar/.claude/worktrees/vault"])
        XCTAssertEqual(
            PathDeflattener.originalPath(for: "-Users-andiyar--claude-worktrees-vault", directoryExists: exists),
            "/Users/andiyar/.claude/worktrees/vault")
    }

    func testLiteralDashInDirectoryName() {
        let exists = existsCheck(for: ["/Users/andiyar/Developer/my-app"])
        XCTAssertEqual(
            PathDeflattener.originalPath(for: "-Users-andiyar-Developer-my-app", directoryExists: exists),
            "/Users/andiyar/Developer/my-app")
    }

    func testSpaceInDirectoryName() {
        let exists = existsCheck(for: ["/Users/andiyar/Desktop/Mail Sort"])
        XCTAssertEqual(
            PathDeflattener.originalPath(for: "-Users-andiyar-Desktop-Mail-Sort", directoryExists: exists),
            "/Users/andiyar/Desktop/Mail Sort")
    }

    func testRootProjectDirectory() {
        // A project dir literally named "-" exists in the real corpus (cwd "/").
        let exists = existsCheck(for: ["/Users"])
        XCTAssertEqual(PathDeflattener.originalPath(for: "-", directoryExists: exists), "/")
    }

    func testSlashPreferredOverLiteralDashOnAmbiguity() {
        // Both /a/Foo/Bar and /a/Foo-Bar exist: "/" is tried first, so the
        // deeper path wins. Documented behavior, not an accident.
        let exists = existsCheck(for: ["/a/Foo/Bar", "/a/Foo-Bar"])
        XCTAssertEqual(
            PathDeflattener.originalPath(for: "-a-Foo-Bar", directoryExists: exists),
            "/a/Foo/Bar")
    }

    func testUnresolvableFallsBackToFlattenedName() {
        let exists = existsCheck(for: [String]())
        XCTAssertEqual(
            PathDeflattener.originalPath(for: "-Gone-project-dir", directoryExists: exists),
            "-Gone-project-dir")
    }

    func testNonFlattenedNamePassesThrough() {
        let exists = existsCheck(for: ["/Users"])
        XCTAssertEqual(
            PathDeflattener.originalPath(for: "no-leading-dash", directoryExists: exists),
            "no-leading-dash")
    }

    func testProjectFolderIdentityAndFallback() {
        let url = URL(fileURLWithPath: "/nonexistent-root/projects/-zzz-not-a-real-path-qqq")
        let folder = ProjectFolder(directoryURL: url)
        XCTAssertEqual(folder.flattenedName, "-zzz-not-a-real-path-qqq")
        XCTAssertEqual(folder.id, folder.flattenedName)
        XCTAssertEqual(folder.originalPath, "-zzz-not-a-real-path-qqq") // fallback
        XCTAssertEqual(folder.directoryURL, url)
    }
}
