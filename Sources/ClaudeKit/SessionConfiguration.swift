import Foundation

public struct SessionConfiguration: Sendable {
    /// nil = resolve `claude` via /usr/bin/env from PATH.
    public var executable: URL?
    public var workingDirectory: URL
    public var model: String?
    public var resumeSessionID: String?
    public var forkSession: Bool = false
    public var permissionMode: String?
    /// Emit Anthropic SSE deltas as `stream_event` lines. On by default:
    /// the conversation UI streams text as it generates.
    public var includePartialMessages = true
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

    public func arguments() -> [String] {
        var args = [
            "-p", "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-prompt-tool", "stdio",
        ]
        if includePartialMessages { args.append("--include-partial-messages") }
        if let model { args += ["--model", model] }
        if let resumeSessionID { args += ["--resume", resumeSessionID] }
        if forkSession { args.append("--fork-session") }
        if let permissionMode { args += ["--permission-mode", permissionMode] }
        args += extraArguments
        return args
    }
}
