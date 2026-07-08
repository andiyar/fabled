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
