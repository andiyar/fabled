import SwiftUI
import ClaudeKit
import FabledCore

/// The quiet, read-only git strip along the very bottom of the conversation
/// view: `branch · +added −removed · cost`. It only *reads* local git state
/// (via `GitInfo`) — no "Create PR" button, no `gh`, no network (that was
/// explicitly cut from v1 by Ben, 2026-07-12).
///
/// Matches the locked mockup's `.cfoot` rule: a full-width strip on
/// `surfaceSide` with a 1px top hairline, ~9/16 padding, 12pt `muted` text,
/// monospaced segments separated by faint `·`. The whole strip is hidden for
/// a non-repo session (when `GitInfo.read` returns nil).
struct GitFooterStrip: View {
    let session: ChatSession
    @State private var info: GitInfo?

    var body: some View {
        // Hidden entirely until/unless we have git state for this session's
        // working directory — a non-repo session shows nothing.
        Group {
            if let info {
                HStack(spacing: Theme.spaceM) {
                    Text(info.branch)
                        .foregroundStyle(Theme.ink)

                    if info.added > 0 || info.removed > 0 {
                        separator
                        HStack(spacing: 6) {
                            Text("+\(info.added)").foregroundStyle(Theme.diffAddColor)
                            Text("−\(info.removed)").foregroundStyle(Theme.diffDelColor)
                        }
                    }

                    if session.cumulativeCostUSD > 0 {
                        separator
                        // Invariant: cumulativeCostUSD is already session-total
                        // — read as-is, never summed (summing double-counts).
                        Text(String(format: "$%.2f", session.cumulativeCostUSD))
                            .foregroundStyle(Theme.muted)
                    }

                    Spacer(minLength: 0)
                }
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, Theme.spaceL)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surfaceSide)
                .overlay(alignment: .top) {
                    Theme.hairline.frame(height: 1)
                }
            }
        }
        // Refresh on appear and whenever a turn boundary is crossed — keying
        // `.task` to `isWorking` + cumulative cost debounces naturally: those
        // change at the START/END of a turn, not per stream delta, so we shell
        // out to `git` at most a couple of times per turn (never per tick).
        .task(id: refreshKey) { await refresh() }
    }

    private var separator: some View {
        Text("·").foregroundStyle(Theme.faint)
    }

    private var refreshKey: String {
        "\(session.isWorking)-\(session.cumulativeCostUSD)"
    }

    private func refresh() async {
        // Best-effort: any failure (or a non-repo directory) leaves `info` nil
        // and the strip stays hidden.
        info = try? await GitInfo.read(at: session.workingDirectory)
    }
}
