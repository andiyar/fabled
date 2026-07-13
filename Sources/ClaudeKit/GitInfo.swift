import Foundation

/// A read-only snapshot of a working directory's git state: the current
/// branch and the working-tree diff line counts. Best-effort — `read`
/// returns nil (never throws) for a non-repo so callers can hide their UI.
///
/// This only *reads* local git via `git`; it never writes, fetches, or talks
/// to any remote. The "Create PR" affordance from the design mockup was cut
/// from v1 (Ben, 2026-07-12), so there is deliberately nothing here but the
/// read.
public struct GitInfo: Sendable, Equatable {
    /// The working tree's name — the last path component of the repo root
    /// (`git rev-parse --show-toplevel`). In a git *worktree* this is the
    /// worktree's own directory name, which is acceptable for the label.
    public let repo: String
    public let branch: String
    public let added: Int
    public let removed: Int

    public init(repo: String, branch: String, added: Int, removed: Int) {
        self.repo = repo
        self.branch = branch
        self.added = added
        self.removed = removed
    }

    /// Reads `git rev-parse --abbrev-ref HEAD` (branch), `git rev-parse
    /// --show-toplevel` (repo name), and `git diff HEAD --numstat` (summed
    /// added/removed columns) in `directory`.
    ///
    /// Returns nil when `directory` is not a git repository (non-zero exit, or
    /// `git` cannot be launched) — it never throws for "not a repo". A repo with
    /// no commits (unborn HEAD) also returns nil: the branch rev-parse exits
    /// non-zero. A `-` in a numstat count means a binary file and is treated as 0.
    ///
    /// Shells out on a dedicated thread, off the cooperative pool: a blocking
    /// `git` read must not park a pool thread (the same scar AgentSession's
    /// dedicated reader threads avoid).
    public static func read(at directory: URL) async throws -> GitInfo? {
        guard let branchRun = await runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: directory),
              branchRun.status == 0 else { return nil }
        let branch = branchRun.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return nil }

        // The repo name is the working tree's last path component. Fetched with
        // the same single-resume, off-main-actor `runGit` as every other command;
        // a failure here → nil, matching the "any failure → nil" contract.
        guard let topRun = await runGit(["rev-parse", "--show-toplevel"], in: directory),
              topRun.status == 0 else { return nil }
        let top = topRun.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !top.isEmpty else { return nil }
        let repo = URL(fileURLWithPath: top).lastPathComponent

        // `git diff HEAD --numstat` counts staged AND unstaged changes to
        // tracked files — plain `git diff` silently drops to 0 once anything is
        // staged. New/untracked files stay uncounted in v1 (no `git status`
        // path, by design). An unborn HEAD makes this fail, but that case is
        // already caught by the branch guard above, so `read` returned nil.
        var added = 0
        var removed = 0
        if let diffRun = await runGit(["diff", "HEAD", "--numstat"], in: directory), diffRun.status == 0 {
            for line in diffRun.output.split(separator: "\n") {
                // numstat is tab-separated: <added>\t<removed>\t<path>.
                // Int("-") is nil → binary files contribute 0, as intended.
                let columns = line.split(separator: "\t")
                guard columns.count >= 2 else { continue }
                added += Int(columns[0]) ?? 0
                removed += Int(columns[1]) ?? 0
            }
        }
        return GitInfo(repo: repo, branch: branch, added: added, removed: removed)
    }

    /// Runs `git <args>` in `directory` on a dedicated thread, returning its
    /// exit status and captured stdout — or nil if the process could not even
    /// be launched (e.g. the directory no longer exists). stderr is discarded
    /// to `/dev/null` so an unread pipe can never block the child.
    private static func runGit(
        _ args: [String], in directory: URL
    ) async -> (status: Int32, output: String)? {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread {
                let process = Process()
                // Resolve `git` via /usr/bin/env so PATH is honored, mirroring
                // AgentSession's CLI spawn rather than hard-coding a location.
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git"] + args
                process.currentDirectoryURL = directory
                let stdout = Pipe()
                process.standardOutput = stdout
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                // Output is small (a branch name / a few numstat lines) and
                // readDataToEndOfFile drains continuously, so this cannot
                // deadlock on a full pipe.
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: (process.terminationStatus, output))
            }
        }
    }
}
