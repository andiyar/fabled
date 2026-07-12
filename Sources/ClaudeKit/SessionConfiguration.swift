import Foundation

public struct SessionConfiguration: Sendable {
    /// nil = resolve `claude` via /usr/bin/env from PATH.
    public var executable: URL?
    public var workingDirectory: URL
    public var model: String?
    public var resumeSessionID: String?
    public var forkSession: Bool = false
    public var permissionMode: String?
    /// Model effort level (low|medium|high|xhigh|max) — Claude Desktop passes
    /// this on every spawn; measured on this repo: `medium` cut first visible
    /// text 24s → 17s (probe finding 1). nil = CLI default.
    public var effort: String?
    /// Emit Anthropic SSE deltas as `stream_event` lines. On by default:
    /// the conversation UI streams text as it generates.
    public var includePartialMessages = true
    /// Extra roots the CLI may access, beyond `workingDirectory`, emitted as
    /// repeated `--add-dir <path>` flags. UX-LEDGER row 33 (dual-use /
    /// multi-folder sessions, e.g. a manuscript folder + a notes folder).
    public var additionalDirectories: [URL] = []
    public var extraArguments: [String] = []

    public init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
    }

    /// Locates the `claude` binary for GUI contexts where PATH is minimal.
    /// LaunchServices hands an app only `/usr/bin:/bin:/usr/sbin:/sbin`, so
    /// `/usr/bin/env claude` (the `executable == nil` fallback) exits 127.
    /// Checks PATH first (Terminal-launched processes carry a full one), then
    /// the standard install locations. Returns nil if none are executable,
    /// leaving the env fallback in place.
    public static func resolveClaudeExecutable(
        environmentPATH: String? = ProcessInfo.processInfo.environment["PATH"],
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        var candidates: [URL] = []
        for dir in (environmentPATH ?? "").split(separator: ":") {
            candidates.append(
                URL(fileURLWithPath: String(dir)).appendingPathComponent("claude"))
        }
        candidates += [
            home.appendingPathComponent(".local/bin/claude"),
            home.appendingPathComponent(".claude/local/claude"),
            URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            URL(fileURLWithPath: "/usr/local/bin/claude"),
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    /// Best-effort CLI version read from the executable's on-disk location,
    /// available at spawn time — unlike `system init`, which 2.1.205+ defers
    /// until the first user turn. The native installer names the real binary
    /// by version (~/.local/bin/claude → ~/.local/share/claude/versions/2.1.205)
    /// and Homebrew keeps a versioned Cellar directory, so after resolving
    /// symlinks the deepest version-shaped path component is the version.
    /// nil when the layout carries no hint; callers fall back to init.
    public static func resolveClaudeVersion(executable: URL) -> String? {
        let versionShaped = /\d+\.\d+\.\d+(?:[-+.][0-9A-Za-z.-]+)?/
        return executable.resolvingSymlinksInPath().pathComponents.reversed()
            .first { $0.wholeMatch(of: versionShaped) != nil }
    }

    public func arguments() -> [String] {
        var args = [
            "-p", "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-prompt-tool", "stdio",
        ]
        if includePartialMessages { args.append("--include-partial-messages") }
        if let model { args += ["--model", model] }
        if let effort { args += ["--effort", effort] }
        if let resumeSessionID { args += ["--resume", resumeSessionID] }
        if forkSession { args.append("--fork-session") }
        if let permissionMode { args += ["--permission-mode", permissionMode] }
        for dir in additionalDirectories { args += ["--add-dir", dir.path] }
        args += extraArguments
        return args
    }
}
