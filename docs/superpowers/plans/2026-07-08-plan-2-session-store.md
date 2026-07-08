# SessionStore + History Search Implementation Plan (Fabled Plan 2 of 4)

> **STATUS: READY FOR EXECUTION.** Expanded from `2026-07-08-plan-2-session-store-brief.md` after empirical probing of the full on-disk corpus (see "Probe findings"). Contract amendments vs the brief are listed below and ledgered in `DECISIONS.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Read, watch, and search every Claude Code session on disk (`~/.claude/projects`) with zero CLI processes — the data layer for Fabled's sidebar and session browser.

**Architecture:** A `TranscriptDecoder` (tolerant, per-line, reusing Plan 1's `AgentEventDecoder` for message lines) feeding a `SessionStore` actor (enumeration, title derivation, transcript loading, change watching via directory kqueue + a cheap mtime poll) and a `SearchIndex` actor (SQLite FTS5 via the system C library, incremental by `(path, mtime, size)`).

**Tech Stack:** Swift 6, SwiftPM, Foundation, system SQLite3 (`import SQLite3` — no package changes, no third-party deps), XCTest. macOS 15+.

**Roadmap context:** Plan 2 of 4. Plan 1 (ClaudeKit engine) is complete and merged. Plan 3 = SwiftUI app shell. Plan 4 = full surfaces. Spec: `docs/superpowers/specs/2026-07-08-fabled-native-client-design.md`.

---

## Probe findings (2026-07-08, Ben's real corpus, CLI ≤ 2.1.202 era files)

Everything below was measured against the full `~/.claude/projects` tree (45 project dirs, 680 main session files, 456 MB main sessions, largest 50.1 MB; plus 235 MB of subagent transcripts nested deeper). The plan's code and tests are built on these facts — trust them over intuition.

1. **There are zero `summary` lines in the corpus.** The brief assumed titles come from `summary` lines; they actually come from `custom-title` lines (user-set, 3430 occurrences) and `ai-title` lines (1262). Shapes:
   `{"type":"custom-title","customTitle":"…","sessionId":"…"}` and `{"type":"ai-title","aiTitle":"…","sessionId":"…"}`. Both can appear multiple times per file (rename history) — **last one wins**. 596 of 680 sessions have no title line at all, so the first-prompt fallback matters. We keep a `.summary` case for older corpora, but it is legacy.
2. **Full line-type census** (all files): `assistant` 66754, `user` 38745, `attachment` 8840, `last-prompt` 6908, `queue-operation` 4929, `mode` 3768, `custom-title` 3430, `system` 2388, `permission-mode` 2194, `file-history-snapshot` 1499, `ai-title` 1262, `agent-name` 865, `started` 142, `result` 44, `worktree-state` 15, `frame-link` 7.
3. **On-disk `user` lines carry real human prompts.** `message.content` is a **string** (4541 lines) for typed prompts, or an **array** (34220 lines) that is either tool results (33608 `tool_result` blocks) or text/image blocks (587 `text`, 247 `image`, 3 `document`). Plan 1's `AgentEventDecoder` maps every `user` line to `.toolResult(...)`, which silently drops prompt text — the transcript decoder MUST handle `user` lines itself.
4. **On-disk `result` lines are NOT turn results.** All 44 have exactly the keys `{type, key, agentId, result}` — they are subagent result caches. Routing them through `AgentEventDecoder` would fabricate garbage `TurnResult`s. Distinguish by the presence of `"key"`.
5. **Wrapper metadata on message lines:** `parentUuid`, `isSidechain`, `uuid`, `timestamp` (ISO8601 with fractional seconds, e.g. `2026-06-12T22:59:49.641Z`), `sessionId`, `cwd`, `gitBranch`, plus sometimes `isMeta` (288), `isCompactSummary` (75), `isVisibleInTranscriptOnly` (75), `agentId`. Compaction leaves a `user` line with `isCompactSummary: true` whose text starts "This session is being continued from a previous conversation…" — it must not become a session title, but it IS worth indexing (it summarizes the session).
6. **Directory layout:** main sessions are `<project>/<uuid>.jsonl` (depth 2 only). Deeper `.jsonl` files exist (`<project>/<session-uuid>/subagents/agent-*.jsonl`, 812 files + 152 deeper) and are OUT of scope for enumeration and search in Plan 2. Project dirs also contain `memory/` subdirectories, `sessions-index.json` (a CLI-maintained cache — do not depend on it), bare-UUID directories, and `.DS_Store` — all must be skipped.
7. **Flattening:** the CLI replaces every non-alphanumeric character of the cwd with `-`. Observed: `/Users/andiyar/.claude/worktrees/x` → `-Users-andiyar--claude-worktrees-x` (note `--` for `/.`), a project dir literally named `-` (cwd `/`), and dirs where `-` stands for a literal dash or space. De-flattening is a filesystem-checked search, not string replacement.
8. **Command/meta prompts:** local-command prompts are stored as user lines whose text starts with `<` (`<command-name>…`, `<local-command-caveat>…`, 22 such lines); title derivation must skip them.
9. **`queue-operation` shapes:** `operation` ∈ {`enqueue` 2468, `dequeue` 2277, `remove` 187, `popAll` 1}, with optional `content` string.

## Contract amendments vs the brief (conscious, ledgered in DECISIONS.md)

- **`TranscriptEntry` is reshaped** to match reality (finding 1, 3, 4): dedicated `userPrompt` and `title` cases, a `LineContext` struct for wrapper metadata, a `sessionMeta` catch-all for known metadata types, `.summary` kept as legacy. The brief's enum could not have produced "zero `.unknown` on real files".
- **`SessionStore.init` gains a defaulted `pollInterval:` parameter**; `reindex()` gains a `@discardableResult -> Int` return (files reindexed) so incremental behavior is testable. Both are source-compatible with the brief's locked signatures.
- **The SQLite wrapper and schema are internal**, not public API. Schema uses rowid encoding `(file_id << 32) | line_no` in a single FTS5 table so per-file re-index deletes are indexed range deletes (no triggers, no external-content table). `files` gains a `title` column so `search()` can build `SessionSummary` without re-scanning session files per hit.
- **Watcher = directory kqueue + 2 s mtime poll.** POSIX directory kqueue does not fire when an existing file is appended to (only entry create/delete/rename), and appends are the main live-update case. A per-file kqueue would need 680+ fds. The poll stats depth-2 entries only (cheap); kqueue gives fast reaction to new/deleted files. FSEventStream stays rejected per the brief.
- **Index scope:** non-sidechain user prompts, non-sidechain assistant text, titles, and summaries (incl. compaction summaries). Sidechain (subagent) traffic and `isMeta` lines are excluded — human-relevant text only, per the brief's intent.

## Verify-by-probing answers (brief §"Verify by probing")

- `summary` lines: **do not exist** in current transcripts (see finding 1); legacy case kept.
- `attachment` lines: `{"parentUuid":…,"isSidechain":…,"attachment":{…},"type":"attachment",…}` — kept opaque (`.attachment(raw:)`).
- Compacted sessions: marker is `isCompactSummary: true` on a `user` line (finding 5); handled in title skip-rules and indexed as text.

---

## Conventions for implementing agents

- Repo root: `~/Developer/Fabled`. All commands run from there.
- Build: `swift build`. Test: `swift test`. Both must be green before every commit. Never commit red.
- Swift 6 strict concurrency is ON. Everything public is `Sendable`. Mutable state lives inside actors (`SessionStore`, `SearchIndex`) only.
- SQLite comes from the macOS SDK: `import SQLite3` — **no `Package.swift` changes**, no linker flags, no third-party wrapper. This is a ledgered decision; do not add GRDB.
- `fixtures/transcripts/` contains real session files from Ben's machine, approved for **local** use only. Do not publish them, quote their content in commit messages, or copy them anywhere outside this repo.
- All new tests are offline. The performance gate (Task 11) is env-gated behind `CLAUDEKIT_PERF=1` because it reads Ben's real `~/.claude/projects`.
- Protocol/decoding ground truth: the fixture files and the "Probe findings" section above. When a shape is in question, open the fixture and look.
- Existing Plan 1 tests must stay green — you are extending `JSONValue.swift` and `AgentEventDecoder.swift`, not rewriting them.

## File structure

```
Sources/ClaudeKit/
  TranscriptEntry.swift      # LineContext + TranscriptEntry (new)
  TranscriptDecoder.swift    # Data line -> TranscriptEntry (new)
  ProjectFolder.swift        # ProjectFolder + PathDeflattener (new)
  SessionSummary.swift       # SessionSummary + SessionFileStamp + JSONLines
                             #   + TitleAccumulator + SessionTitle (new)
  SessionStore.swift         # actor: projects/sessions/transcript/changes (new)
  DirectoryWatcher.swift     # kqueue dispatch sources (new)
  SQLiteDatabase.swift       # minimal system-SQLite wrapper, internal (new)
  SearchIndex.swift          # actor: schema, incremental reindex, FTS5 search (new)
  JSONValue.swift            # MODIFY: add init(parsing:) fast path
  AgentEventDecoder.swift    # MODIFY: split out decode(raw:) overload
Tests/ClaudeKitTests/
  TranscriptFixturesTests.swift
  JSONValueParsingTests.swift
  TranscriptDecoderTests.swift
  ProjectFolderTests.swift
  SessionTitleTests.swift
  SessionStoreTests.swift
  SQLiteDatabaseTests.swift
  SearchIndexTests.swift
  SessionWatcherTests.swift
  PerformanceGateTests.swift # env-gated: CLAUDEKIT_PERF=1
  Fixtures.swift             # MODIFY: transcript fixture loaders
fixtures/transcripts/
  README.md                  # provenance + do-not-publish warning (new)
  real-titled-session.jsonl    # already copied during plan-writing (28 lines)
  real-tooluse-session.jsonl   # already copied during plan-writing (141 lines)
  real-untitled-session.jsonl  # already copied during plan-writing (11 lines)
  synthetic-edge-cases.jsonl   # created in Task 1 (22 lines)
```

**Fixture provenance (recorded 2026-07-08):** the three `real-*` files were copied during plan-writing from
`-Users-andiyar-Developer-oni/97c70bda-ac5d-4e12-982e-8e6e35dd2674.jsonl` (titled, 28 lines),
`-Users-andiyar-Developer-oni/21feb0f8-e41a-4f72-9efb-9232b5bb64de.jsonl` (tool use, 141 lines),
`-Users-andiyar-Developer-Fabled/036b246d-0898-4ace-89b2-8fdd6c107fc4.jsonl` (untitled "pong" session, 11 lines).
Their exact line counts, titles, and per-type censuses are baked into tests below — do not re-copy or edit these files.

---

### Task 1: Transcript fixtures — README, synthetic edge-case file, loaders

**Files:**
- Create: `fixtures/transcripts/README.md`
- Create: `fixtures/transcripts/synthetic-edge-cases.jsonl`
- Modify: `Tests/ClaudeKitTests/Fixtures.swift`
- Create: `Tests/ClaudeKitTests/TranscriptFixturesTests.swift`

- [ ] **Step 1: Verify the three real fixtures are present**

Run: `wc -l fixtures/transcripts/*.jsonl`
Expected output includes:
```
      28 fixtures/transcripts/real-titled-session.jsonl
     141 fixtures/transcripts/real-tooluse-session.jsonl
      11 fixtures/transcripts/real-untitled-session.jsonl
```
If any file is missing, STOP and report to the coordinator — do not re-copy from `~/.claude/projects` yourself (the sources may have changed since plan-writing).

- [ ] **Step 2: Write fixtures/transcripts/README.md**

```markdown
# Transcript fixtures

Real Claude Code session files copied from Ben's `~/.claude/projects` on
2026-07-08, plus one hand-written synthetic file. Ben approved **local use
only**: do not publish this repository, quote fixture content in commit
messages, or copy these files elsewhere.

| file | lines | purpose |
|---|---|---|
| real-titled-session.jsonl | 28 | custom-title lines (6 of them — last-wins), mode/last-prompt metadata, a system line |
| real-tooluse-session.jsonl | 141 | tool_result user lines (24), assistant turns (60), 15 custom-titles |
| real-untitled-session.jsonl | 11 | no title lines — first-prompt fallback ("Reply with exactly: pong") |
| synthetic-edge-cases.jsonl | 22 | hand-written: legacy summary, ai-title, sidechain/meta/compact prompts, image blocks, result-cache line, unknown type |

The real files are byte-exact snapshots; tests assert their exact line
counts and titles. Never edit them. Extend `synthetic-edge-cases.jsonl`
instead (and update the census constants in TranscriptDecoderTests).
```

- [ ] **Step 3: Write fixtures/transcripts/synthetic-edge-cases.jsonl**

Exactly these 22 lines (each is one line in the file, no blank lines; the file ends with a trailing newline):

```jsonl
{"type":"summary","summary":"Legacy summary title","leafUuid":"00000000-0000-0000-0000-000000000001"}
{"type":"ai-title","aiTitle":"Synthetic AI title","sessionId":"11111111-1111-1111-1111-111111111111"}
{"parentUuid":null,"isSidechain":true,"agentId":"a1","type":"user","message":{"role":"user","content":"sidechain subagent prompt zebra"},"uuid":"00000000-0000-0000-0000-000000000003","timestamp":"2026-07-08T00:00:01.000Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"parentUuid":null,"isSidechain":false,"isMeta":true,"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"},"uuid":"00000000-0000-0000-0000-000000000004","timestamp":"2026-07-08T00:00:02.000Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"parentUuid":null,"isSidechain":false,"isCompactSummary":true,"isVisibleInTranscriptOnly":true,"type":"user","message":{"role":"user","content":"This session is being continued from a previous conversation. Summary: built the flux capacitor."},"uuid":"00000000-0000-0000-0000-000000000005","timestamp":"2026-07-08T00:00:03.000Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"first real synthetic prompt about wombats"},"uuid":"00000000-0000-0000-0000-000000000006","timestamp":"2026-07-08T00:00:04.123Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"look at this screenshot please"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo="}}]},"uuid":"00000000-0000-0000-0000-000000000007","timestamp":"2026-07-08T00:00:05Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"parentUuid":"00000000-0000-0000-0000-000000000007","isSidechain":false,"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"file contents here","is_error":false}]},"toolUseResult":"file contents here","uuid":"00000000-0000-0000-0000-000000000008","timestamp":"2026-07-08T00:00:06.000Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"parentUuid":"00000000-0000-0000-0000-000000000008","isSidechain":false,"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"assistant reply about wombats and marsupials"}]},"requestId":"req_1","uuid":"00000000-0000-0000-0000-000000000009","timestamp":"2026-07-08T00:00:07.000Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"type":"result","key":"v2:deadbeefcafe","agentId":"a2","result":{"components":[{"dir":"/tmp/x","role":"demo"}]}}
{"type":"started","key":"v2:deadbeefcafe","agentId":"a2"}
{"type":"worktree-state","worktreeSession":{"originalCwd":"/tmp","worktreePath":"/tmp/.claude/worktrees/demo","worktreeName":"demo","worktreeBranch":"feat/demo","sessionId":"11111111-1111-1111-1111-111111111111","enteredExisting":false},"sessionId":"11111111-1111-1111-1111-111111111111"}
{"type":"frame-link","sessionId":"11111111-1111-1111-1111-111111111111","path":"/tmp/scratch/page.html","frameUrl":"https://claude.ai/code/artifact/00000000","timestamp":"2026-07-08T00:00:08.000Z"}
{"type":"file-history-snapshot","messageId":"00000000-0000-0000-0000-00000000000a","snapshot":{"messageId":"00000000-0000-0000-0000-00000000000a","trackedFileBackups":{},"timestamp":"2026-07-08T00:00:09.000Z"},"isSnapshotUpdate":false}
{"type":"permission-mode","permissionMode":"default","sessionId":"11111111-1111-1111-1111-111111111111"}
{"type":"agent-name","agentName":"Synthetic Agent","sessionId":"11111111-1111-1111-1111-111111111111"}
{"type":"mode","mode":"normal","sessionId":"11111111-1111-1111-1111-111111111111"}
{"type":"last-prompt","lastPrompt":"first real synthetic prompt about wombats","leafUuid":"00000000-0000-0000-0000-000000000006","sessionId":"11111111-1111-1111-1111-111111111111"}
{"type":"queue-operation","operation":"enqueue","timestamp":"2026-07-08T00:00:10.000Z","sessionId":"11111111-1111-1111-1111-111111111111","content":"queued follow-up prompt"}
{"parentUuid":null,"isSidechain":false,"attachment":{"type":"hook_success","hookName":"SessionStart:startup","content":""},"type":"attachment","uuid":"00000000-0000-0000-0000-00000000000b","timestamp":"2026-07-08T00:00:11.000Z","sessionId":"11111111-1111-1111-1111-111111111111"}
{"type":"flux-capacitor","payload":{"charge":88}}
{"type":"custom-title","customTitle":"Synthetic custom title","sessionId":"11111111-1111-1111-1111-111111111111"}
```

- [ ] **Step 4: Add transcript loaders to Tests/ClaudeKitTests/Fixtures.swift**

Append inside the existing `enum Fixtures`:

```swift
    static var transcriptsDir: URL {
        fixturesDir.appendingPathComponent("transcripts")
    }

    static func transcriptLines(_ name: String) throws -> [Data] {
        let url = transcriptsDir.appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map { Data($0.utf8) }
    }

    static func transcriptData(_ name: String) throws -> Data {
        try Data(contentsOf: transcriptsDir.appendingPathComponent(name))
    }
```

- [ ] **Step 5: Write the failing test**

`Tests/ClaudeKitTests/TranscriptFixturesTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class TranscriptFixturesTests: XCTestCase {
    func testFixtureInventory() throws {
        XCTAssertEqual(try Fixtures.transcriptLines("real-titled-session.jsonl").count, 28)
        XCTAssertEqual(try Fixtures.transcriptLines("real-tooluse-session.jsonl").count, 141)
        XCTAssertEqual(try Fixtures.transcriptLines("real-untitled-session.jsonl").count, 11)
        XCTAssertEqual(try Fixtures.transcriptLines("synthetic-edge-cases.jsonl").count, 22)
    }

    func testEveryFixtureLineIsValidJSONObjectWithType() throws {
        for name in ["real-titled-session.jsonl", "real-tooluse-session.jsonl",
                     "real-untitled-session.jsonl", "synthetic-edge-cases.jsonl"] {
            for (index, line) in try Fixtures.transcriptLines(name).enumerated() {
                let object = try JSONSerialization.jsonObject(with: line)
                let dictionary = try XCTUnwrap(object as? [String: Any], "\(name):\(index + 1)")
                XCTAssertNotNil(dictionary["type"] as? String, "\(name):\(index + 1) has no type")
            }
        }
    }
}
```

- [ ] **Step 6: Run the tests and make sure they pass**

Run: `swift test --filter TranscriptFixturesTests`
Expected: 2 tests pass. (These pass immediately once the synthetic file is exact — the "failing" state here is any typo in the synthetic file.)

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: all tests pass (25 existing + 2 new).

- [ ] **Step 8: Commit**

```bash
git add fixtures/transcripts Tests/ClaudeKitTests/Fixtures.swift Tests/ClaudeKitTests/TranscriptFixturesTests.swift
git commit -m "test: transcript fixtures (3 real sessions + synthetic edge cases) with loaders"
```

---

### Task 2: JSONValue bulk-parsing fast path + AgentEventDecoder.decode(raw:)

Transcript decoding parses multi-MB files line by line; `JSONDecoder` is the slow path (it re-tokenizes through `Decodable` machinery). `JSONSerialization` is ~3-4x faster for this shape of work. Also split `AgentEventDecoder.decode` so an already-parsed `JSONValue` can be decoded without re-parsing bytes.

**Files:**
- Modify: `Sources/ClaudeKit/JSONValue.swift`
- Modify: `Sources/ClaudeKit/AgentEventDecoder.swift`
- Create: `Tests/ClaudeKitTests/JSONValueParsingTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/JSONValueParsingTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class JSONValueParsingTests: XCTestCase {
    /// The fast path must agree with the Plan 1 JSONDecoder path on every
    /// line of every fixture we have — protocol captures and transcripts.
    func testParsingMatchesJSONDecoderAcrossAllFixtures() throws {
        let fixtureDirs = [Fixtures.fixturesDir, Fixtures.transcriptsDir]
        var lineCount = 0
        for dir in fixtureDirs {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)
            for url in files where url.pathExtension == "jsonl" {
                let text = try String(contentsOf: url, encoding: .utf8)
                for lineText in text.split(separator: "\n") {
                    let line = Data(lineText.utf8)
                    let fast = try JSONValue(parsing: line)
                    let reference = try JSONDecoder().decode(JSONValue.self, from: line)
                    XCTAssertEqual(fast, reference, "mismatch in \(url.lastPathComponent)")
                    lineCount += 1
                }
            }
        }
        XCTAssertGreaterThan(lineCount, 200, "fixture sweep looks too small to be real")
    }

    func testParsingScalarsAndStructure() throws {
        XCTAssertEqual(try JSONValue(parsing: Data("42".utf8)), .number(42))
        XCTAssertEqual(try JSONValue(parsing: Data("true".utf8)), .bool(true))
        XCTAssertEqual(try JSONValue(parsing: Data("null".utf8)), .null)
        XCTAssertEqual(try JSONValue(parsing: Data(#""hi""#.utf8)), .string("hi"))
        XCTAssertEqual(
            try JSONValue(parsing: Data(#"{"a":[1,false,"x"]}"#.utf8)),
            .object(["a": .array([.number(1), .bool(false), .string("x")])]))
    }

    func testParsingRejectsGarbage() {
        XCTAssertThrowsError(try JSONValue(parsing: Data("not json".utf8)))
    }

    func testDecodeRawMatchesDecodeLine() throws {
        let line = Fixtures.initLine
        let fromLine = try AgentEventDecoder.decode(line)
        let fromRaw = AgentEventDecoder.decode(raw: try JSONValue(parsing: line))
        guard case .systemInit(let a) = fromLine, case .systemInit(let b) = fromRaw else {
            return XCTFail("expected systemInit from both paths")
        }
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter JSONValueParsingTests`
Expected: FAIL to compile — `JSONValue` has no `init(parsing:)`, `AgentEventDecoder` has no `decode(raw:)`.

- [ ] **Step 3: Add init(parsing:) to Sources/ClaudeKit/JSONValue.swift**

Append at the end of the file:

```swift
import Foundation

extension JSONValue {
    /// Bulk-parsing fast path used by transcript decoding, where whole
    /// multi-MB session files are parsed line by line. JSONSerialization is
    /// several times faster than JSONDecoder for this workload; the guard
    /// test proves both paths produce identical values on every fixture.
    public init(parsing data: Data) throws {
        self = Self.bridge(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    private static func bridge(_ object: Any) -> JSONValue {
        switch object {
        case let dictionary as [String: Any]:
            return .object(dictionary.mapValues(bridge))
        case let array as [Any]:
            return .array(array.map(bridge))
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        default:
            return .null
        }
    }
}
```

- [ ] **Step 4: Split AgentEventDecoder.decode**

In `Sources/ClaudeKit/AgentEventDecoder.swift`, replace:

```swift
    public static func decode(_ line: Data) throws -> AgentEvent {
        let raw = try JSONDecoder().decode(JSONValue.self, from: line)
```

with:

```swift
    public static func decode(_ line: Data) throws -> AgentEvent {
        try decode(raw: JSONDecoder().decode(JSONValue.self, from: line))
    }

    public static func decode(raw: JSONValue) -> AgentEvent {
```

and delete the now-duplicated `let raw` line so the rest of the original method body becomes the body of `decode(raw:)`. No other logic changes — the whole existing `switch` stays byte-identical.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter JSONValueParsingTests`
Expected: 4 tests PASS.

- [ ] **Step 6: Run the full suite (Plan 1 regression check)**

Run: `swift test`
Expected: all tests pass, including every existing AgentEventDecoderTests case.

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeKit/JSONValue.swift Sources/ClaudeKit/AgentEventDecoder.swift Tests/ClaudeKitTests/JSONValueParsingTests.swift
git commit -m "feat: JSONValue(parsing:) fast path and AgentEventDecoder.decode(raw:) overload"
```

---

### Task 3: LineContext + TranscriptEntry + TranscriptDecoder

The core of Plan 2's decoding: every line of an on-disk session file becomes exactly one `TranscriptEntry`, and on the three real fixtures the decoder must produce **zero** `.unknown` entries.

**Files:**
- Create: `Sources/ClaudeKit/TranscriptEntry.swift`
- Create: `Sources/ClaudeKit/TranscriptDecoder.swift`
- Create: `Tests/ClaudeKitTests/TranscriptDecoderTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/TranscriptDecoderTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

/// Counts entries per TranscriptEntry case across a decoded file.
struct EntryCensus: Equatable {
    var userPrompt = 0, event = 0, title = 0, summary = 0
    var queueOperation = 0, attachment = 0, sessionMeta = 0, unknown = 0

    var total: Int {
        userPrompt + event + title + summary + queueOperation + attachment + sessionMeta + unknown
    }

    static func of(_ lines: [Data]) throws -> EntryCensus {
        var census = EntryCensus()
        for line in lines {
            switch try TranscriptDecoder.decode(line) {
            case .userPrompt: census.userPrompt += 1
            case .event: census.event += 1
            case .title: census.title += 1
            case .summary: census.summary += 1
            case .queueOperation: census.queueOperation += 1
            case .attachment: census.attachment += 1
            case .sessionMeta: census.sessionMeta += 1
            case .unknown: census.unknown += 1
            }
        }
        return census
    }
}

final class TranscriptDecoderTests: XCTestCase {

    // MARK: whole-file censuses (exact values measured 2026-07-08)

    func testRealTitledSessionCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("real-titled-session.jsonl"))
        XCTAssertEqual(census.userPrompt, 6)
        XCTAssertEqual(census.event, 2)        // 1 assistant + 1 system
        XCTAssertEqual(census.title, 6)        // custom-title x6
        XCTAssertEqual(census.summary, 0)
        XCTAssertEqual(census.queueOperation, 4)
        XCTAssertEqual(census.attachment, 5)
        XCTAssertEqual(census.sessionMeta, 5)  // last-prompt x2 + mode x3
        XCTAssertEqual(census.unknown, 0, "zero-unknown gate")
        XCTAssertEqual(census.total, 28)
    }

    func testRealTooluseSessionCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("real-tooluse-session.jsonl"))
        XCTAssertEqual(census.userPrompt, 5)   // 3 string prompts + 2 text-block prompts
        XCTAssertEqual(census.event, 85)       // 60 assistant + 1 system + 24 tool-result user lines
        XCTAssertEqual(census.title, 15)
        XCTAssertEqual(census.queueOperation, 6)
        XCTAssertEqual(census.attachment, 15)
        XCTAssertEqual(census.sessionMeta, 15) // last-prompt x12 + mode x3
        XCTAssertEqual(census.unknown, 0, "zero-unknown gate")
        XCTAssertEqual(census.total, 141)
    }

    func testRealUntitledSessionCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("real-untitled-session.jsonl"))
        XCTAssertEqual(census.userPrompt, 1)
        XCTAssertEqual(census.event, 2)        // 2 assistant
        XCTAssertEqual(census.title, 0)
        XCTAssertEqual(census.queueOperation, 2)
        XCTAssertEqual(census.attachment, 5)
        XCTAssertEqual(census.sessionMeta, 1)  // last-prompt
        XCTAssertEqual(census.unknown, 0, "zero-unknown gate")
        XCTAssertEqual(census.total, 11)
    }

    func testSyntheticEdgeCasesCensus() throws {
        let census = try EntryCensus.of(try Fixtures.transcriptLines("synthetic-edge-cases.jsonl"))
        XCTAssertEqual(census.userPrompt, 5)   // sidechain, meta, compact, plain, text+image
        XCTAssertEqual(census.event, 2)        // tool_result user + assistant
        XCTAssertEqual(census.title, 2)        // ai-title + custom-title
        XCTAssertEqual(census.summary, 1)
        XCTAssertEqual(census.queueOperation, 1)
        XCTAssertEqual(census.attachment, 1)
        XCTAssertEqual(census.sessionMeta, 9)  // result-cache, started, worktree-state, frame-link,
                                               // file-history-snapshot, permission-mode, agent-name,
                                               // mode, last-prompt
        XCTAssertEqual(census.unknown, 1)      // flux-capacitor
        XCTAssertEqual(census.total, 22)
    }

    // MARK: individual decode branches

    private func decode(_ json: String) throws -> TranscriptEntry {
        try TranscriptDecoder.decode(Data(json.utf8))
    }

    func testStringUserPrompt() throws {
        let entry = try decode(#"{"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"first real synthetic prompt about wombats"},"uuid":"00000000-0000-0000-0000-000000000006","timestamp":"2026-07-08T00:00:04.123Z","sessionId":"s"}"#)
        guard case .userPrompt(let text, let context, _) = entry else {
            return XCTFail("expected userPrompt, got \(entry)")
        }
        XCTAssertEqual(text, "first real synthetic prompt about wombats")
        XCTAssertFalse(context.isSidechain)
        XCTAssertFalse(context.isMeta)
        XCTAssertFalse(context.isCompactSummary)
        XCTAssertEqual(context.uuid, "00000000-0000-0000-0000-000000000006")
        let timestamp = try XCTUnwrap(context.timestamp)
        XCTAssertEqual(timestamp.timeIntervalSince1970, 1_783_468_804.123, accuracy: 0.001)
    }

    func testTimestampWithoutFractionalSeconds() throws {
        let entry = try decode(#"{"type":"user","isSidechain":false,"message":{"role":"user","content":"x"},"timestamp":"2026-07-08T00:00:05Z"}"#)
        guard case .userPrompt(_, let context, _) = entry else { return XCTFail() }
        let timestamp = try XCTUnwrap(context.timestamp)
        XCTAssertEqual(timestamp.timeIntervalSince1970, 1_783_468_805, accuracy: 0.001)
    }

    func testTextBlockArrayUserPrompt() throws {
        let entry = try decode(#"{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"type":"text","text":"look at this screenshot please"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBORw0KGgo="}}]}}"#)
        guard case .userPrompt(let text, _, _) = entry else {
            return XCTFail("expected userPrompt, got \(entry)")
        }
        XCTAssertEqual(text, "look at this screenshot please")
    }

    func testToolResultUserLineBecomesEvent() throws {
        let entry = try decode(#"{"type":"user","isSidechain":false,"message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"file contents here","is_error":false}]}}"#)
        guard case .event(.toolResult(let results), _) = entry else {
            return XCTFail("expected event(.toolResult), got \(entry)")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolUseID, "toolu_01")
        XCTAssertFalse(results[0].isError)
    }

    func testSidechainFlagsSurfaceInContext() throws {
        let entry = try decode(#"{"parentUuid":null,"isSidechain":true,"agentId":"a1","type":"user","message":{"role":"user","content":"sidechain subagent prompt zebra"}}"#)
        guard case .userPrompt(_, let context, _) = entry else { return XCTFail() }
        XCTAssertTrue(context.isSidechain)
        XCTAssertEqual(context.agentID, "a1")
    }

    func testAssistantLineBecomesEvent() throws {
        let entry = try decode(#"{"isSidechain":false,"type":"assistant","message":{"role":"assistant","model":"claude-opus-4-8","content":[{"type":"text","text":"assistant reply about wombats and marsupials"}]},"uuid":"u9"}"#)
        guard case .event(.assistant(let message), let context) = entry else {
            return XCTFail("expected event(.assistant), got \(entry)")
        }
        XCTAssertEqual(message.content, [.text("assistant reply about wombats and marsupials")])
        XCTAssertEqual(context.uuid, "u9")
    }

    func testCustomAndAITitles() throws {
        let custom = try decode(#"{"type":"custom-title","customTitle":"Synthetic custom title","sessionId":"s"}"#)
        guard case .title("Synthetic custom title", isCustom: true, _) = custom else {
            return XCTFail("expected custom title, got \(custom)")
        }
        let ai = try decode(#"{"type":"ai-title","aiTitle":"Synthetic AI title","sessionId":"s"}"#)
        guard case .title("Synthetic AI title", isCustom: false, _) = ai else {
            return XCTFail("expected ai title, got \(ai)")
        }
    }

    func testLegacySummary() throws {
        let entry = try decode(#"{"type":"summary","summary":"Legacy summary title","leafUuid":"l1"}"#)
        guard case .summary(let text, _) = entry else { return XCTFail() }
        XCTAssertEqual(text, "Legacy summary title")
    }

    func testQueueOperation() throws {
        let entry = try decode(#"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-07-08T00:00:10.000Z","sessionId":"s","content":"queued follow-up prompt"}"#)
        guard case .queueOperation(let operation, let content, _) = entry else { return XCTFail() }
        XCTAssertEqual(operation, "enqueue")
        XCTAssertEqual(content, "queued follow-up prompt")
    }

    func testResultCacheLineIsSessionMetaNotTurnResult() throws {
        let entry = try decode(#"{"type":"result","key":"v2:deadbeefcafe","agentId":"a2","result":{"x":1}}"#)
        guard case .sessionMeta(let type, _) = entry else {
            return XCTFail("result-cache lines must not decode as TurnResult; got \(entry)")
        }
        XCTAssertEqual(type, "result")
    }

    func testUnknownTypeIsPreservedNotThrown() throws {
        let entry = try decode(#"{"type":"flux-capacitor","payload":{"charge":88}}"#)
        guard case .unknown(let raw) = entry else { return XCTFail() }
        XCTAssertEqual(raw["type"]?.stringValue, "flux-capacitor")
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try TranscriptDecoder.decode(Data("not json at all".utf8)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter TranscriptDecoderTests`
Expected: FAIL to compile — `TranscriptEntry`, `LineContext`, `TranscriptDecoder` don't exist.

- [ ] **Step 3: Write Sources/ClaudeKit/TranscriptEntry.swift**

```swift
import Foundation

/// Wrapper metadata carried by message lines (user/assistant/system) in
/// on-disk session files. Absent fields default to false/nil — many line
/// types carry none of this.
public struct LineContext: Sendable, Equatable {
    public let uuid: String?
    public let parentUUID: String?
    public let timestamp: Date?
    public let isSidechain: Bool
    public let isMeta: Bool
    public let isCompactSummary: Bool
    public let agentID: String?

    public init(raw: JSONValue) {
        self.uuid = raw["uuid"]?.stringValue
        self.parentUUID = raw["parentUuid"]?.stringValue
        self.timestamp = raw["timestamp"]?.stringValue.flatMap(Self.parseTimestamp)
        self.isSidechain = raw["isSidechain"]?.boolValue ?? false
        self.isMeta = raw["isMeta"]?.boolValue ?? false
        self.isCompactSummary = raw["isCompactSummary"]?.boolValue ?? false
        self.agentID = raw["agentId"]?.stringValue
    }

    /// Transcript timestamps are ISO8601, usually with fractional seconds
    /// ("2026-06-12T22:59:49.641Z") but occasionally without.
    static func parseTimestamp(_ string: String) -> Date? {
        (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(string, strategy: Date.ISO8601FormatStyle()))
    }
}

/// One line of an on-disk session transcript. The on-disk format is a
/// superset of the live stream: it interleaves conversation events with
/// titles, queue bookkeeping, and session metadata.
public enum TranscriptEntry: Sendable {
    /// A human-typed prompt: `user` line whose content is a string or a
    /// block array without tool results.
    case userPrompt(text: String, context: LineContext, raw: JSONValue)
    /// Anything Plan 1's AgentEventDecoder understands: assistant turns,
    /// tool results, system events.
    case event(AgentEvent, context: LineContext)
    /// `custom-title` (user-set, isCustom: true) or `ai-title` lines.
    /// Later occurrences override earlier ones.
    case title(text: String, isCustom: Bool, raw: JSONValue)
    /// Legacy `summary` lines. None exist in the 2026-07 corpus; kept for
    /// older session files.
    case summary(text: String, raw: JSONValue)
    case queueOperation(operation: String, content: String?, raw: JSONValue)
    case attachment(raw: JSONValue)
    /// Known bookkeeping line types (mode, last-prompt, file-history-snapshot,
    /// subagent result caches, ...). Typed loosely on purpose.
    case sessionMeta(type: String, raw: JSONValue)
    case unknown(raw: JSONValue)
}
```

- [ ] **Step 4: Write Sources/ClaudeKit/TranscriptDecoder.swift**

```swift
import Foundation

public enum TranscriptDecoder {
    /// Session-metadata line types observed across the full on-disk corpus
    /// (2026-07-08 census). New CLI line types deliberately fall through to
    /// `.unknown` instead — that is the protocol-drift insurance working.
    static let sessionMetaTypes: Set<String> = [
        "mode", "permission-mode", "last-prompt", "file-history-snapshot",
        "agent-name", "started", "worktree-state", "frame-link",
    ]

    /// Decodes one transcript line. Throws only when the line is not JSON;
    /// every well-formed JSON object decodes to some entry.
    public static func decode(_ line: Data) throws -> TranscriptEntry {
        let raw = try JSONValue(parsing: line)
        let type = raw["type"]?.stringValue ?? ""
        switch type {
        case "user":
            return decodeUser(raw)
        case "assistant", "system":
            return .event(AgentEventDecoder.decode(raw: raw), context: LineContext(raw: raw))
        case "custom-title":
            return .title(text: raw["customTitle"]?.stringValue ?? "", isCustom: true, raw: raw)
        case "ai-title":
            return .title(text: raw["aiTitle"]?.stringValue ?? "", isCustom: false, raw: raw)
        case "summary":
            return .summary(text: raw["summary"]?.stringValue ?? "", raw: raw)
        case "queue-operation":
            return .queueOperation(
                operation: raw["operation"]?.stringValue ?? "",
                content: raw["content"]?.stringValue,
                raw: raw)
        case "attachment":
            return .attachment(raw: raw)
        case "result" where raw["key"] != nil:
            // On-disk `result` lines are subagent result caches (key +
            // agentId), NOT turn results — never route them through
            // AgentEventDecoder, which would fabricate a TurnResult.
            return .sessionMeta(type: type, raw: raw)
        case let known where sessionMetaTypes.contains(known):
            return .sessionMeta(type: type, raw: raw)
        default:
            return .unknown(raw: raw)
        }
    }

    private static func decodeUser(_ raw: JSONValue) -> TranscriptEntry {
        let context = LineContext(raw: raw)
        let content = raw["message"]?["content"]
        if let text = content?.stringValue {
            return .userPrompt(text: text, context: context, raw: raw)
        }
        let blocks = content?.arrayValue ?? []
        let hasToolResult = blocks.contains { $0["type"]?.stringValue == "tool_result" }
        if hasToolResult {
            return .event(AgentEventDecoder.decode(raw: raw), context: context)
        }
        let text = blocks
            .compactMap { block -> String? in
                guard block["type"]?.stringValue == "text" else { return nil }
                return block["text"]?.stringValue
            }
            .joined(separator: "\n")
        return .userPrompt(text: text, context: context, raw: raw)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter TranscriptDecoderTests`
Expected: all 16 tests PASS. If a census number is off by one, diff your decoder's routing against the "Probe findings" table before touching the fixture — the fixture is ground truth.

- [ ] **Step 6: Run the full suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeKit/TranscriptEntry.swift Sources/ClaudeKit/TranscriptDecoder.swift Tests/ClaudeKitTests/TranscriptDecoderTests.swift
git commit -m "feat: TranscriptEntry + tolerant TranscriptDecoder (zero-unknown on real fixtures)"
```

---

### Task 4: ProjectFolder + de-flattening heuristic

**Files:**
- Create: `Sources/ClaudeKit/ProjectFolder.swift`
- Create: `Tests/ClaudeKitTests/ProjectFolderTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/ProjectFolderTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ProjectFolderTests`
Expected: FAIL to compile — `PathDeflattener` and `ProjectFolder` don't exist.

- [ ] **Step 3: Write Sources/ClaudeKit/ProjectFolder.swift**

```swift
import Foundation

/// One directory under `~/.claude/projects`, i.e. one working directory the
/// CLI has ever been run in.
public struct ProjectFolder: Sendable, Hashable, Identifiable {
    public var id: String { flattenedName }
    /// e.g. "-Users-andiyar-Developer-Wine"
    public let flattenedName: String
    /// Best-effort de-flattened path, e.g. "/Users/andiyar/Developer/Wine".
    /// Falls back to `flattenedName` when no candidate path exists on disk.
    public let originalPath: String
    public let directoryURL: URL

    public init(flattenedName: String, originalPath: String, directoryURL: URL) {
        self.flattenedName = flattenedName
        self.originalPath = originalPath
        self.directoryURL = directoryURL
    }

    /// Resolves `originalPath` against the real filesystem.
    public init(directoryURL: URL) {
        let name = directoryURL.lastPathComponent
        self.init(
            flattenedName: name,
            originalPath: PathDeflattener.originalPath(
                for: name, directoryExists: PathDeflattener.realDirectoryExists),
            directoryURL: directoryURL)
    }
}

/// The CLI flattens a session's cwd into a directory name by replacing every
/// non-alphanumeric character with "-". Recovery is ambiguous ("-" may have
/// been "/", ".", " ", "_" or a literal dash), so we search for a path that
/// actually exists, preferring "/" so deeper paths win ties.
enum PathDeflattener {
    /// Characters a "-" may stand for, tried in this order.
    static let joiners = ["/", "-", ".", " ", "_"]
    /// Search-state budget: bounds worst-case cost for unresolvable names
    /// (each state is at most one directory-existence check).
    static let maxStates = 4096

    static let realDirectoryExists: @Sendable (String) -> Bool = { path in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    static func originalPath(
        for flattenedName: String,
        directoryExists: (String) -> Bool
    ) -> String {
        let segments = flattenedName
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)
        guard segments.count >= 2, segments[0].isEmpty else { return flattenedName }
        var budget = maxStates
        if let hit = search(
            prefix: "/" + segments[1],
            segments: segments,
            index: 2,
            directoryExists: directoryExists,
            budget: &budget
        ) {
            return hit
        }
        return flattenedName
    }

    /// Depth-first: at each remaining "-" try every joiner. Descending with
    /// "/" requires the prefix so far to be an existing directory, which
    /// prunes almost everything; other joiners just extend the current path
    /// component and are validated at the next "/" or at the end.
    private static func search(
        prefix: String,
        segments: [String],
        index: Int,
        directoryExists: (String) -> Bool,
        budget: inout Int
    ) -> String? {
        guard budget > 0 else { return nil }
        budget -= 1
        if index == segments.count {
            return directoryExists(prefix) ? prefix : nil
        }
        for joiner in joiners {
            if joiner == "/" {
                guard !prefix.hasSuffix("/"), directoryExists(prefix) else { continue }
            }
            if let hit = search(
                prefix: prefix + joiner + segments[index],
                segments: segments,
                index: index + 1,
                directoryExists: directoryExists,
                budget: &budget
            ) {
                return hit
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ProjectFolderTests`
Expected: all 9 tests PASS.

- [ ] **Step 5: Run the full suite, then commit**

Run: `swift test` — all green, then:

```bash
git add Sources/ClaudeKit/ProjectFolder.swift Tests/ClaudeKitTests/ProjectFolderTests.swift
git commit -m "feat: ProjectFolder with filesystem-checked de-flattening heuristic"
```

---

### Task 5: JSONLines + TitleAccumulator + SessionTitle

Title derivation must not JSON-parse every line of a 50 MB file: only the first 100 lines are decoded (first-prompt fallback), plus any short line containing a title key.

**Files:**
- Create: `Sources/ClaudeKit/SessionSummary.swift` (this task: everything except the `SessionSummary` struct itself, which lands in Task 6 — see the file layout in the step)
- Create: `Tests/ClaudeKitTests/SessionTitleTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/SessionTitleTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class SessionTitleTests: XCTestCase {

    // MARK: JSONLines

    private func lines(_ text: String) -> [String] {
        var result: [String] = []
        var iterator = JSONLines(data: Data(text.utf8))
        while let line = iterator.next() {
            result.append(String(decoding: line, as: UTF8.self))
        }
        return result
    }

    func testJSONLinesSplitsAndSkipsBlanks() {
        XCTAssertEqual(lines("a\nb\n"), ["a", "b"])
        XCTAssertEqual(lines("a\n\n\nb"), ["a", "b"])   // blank lines skipped
        XCTAssertEqual(lines("a"), ["a"])                // no trailing newline
        XCTAssertEqual(lines(""), [])
        XCTAssertEqual(lines("\n\n"), [])
    }

    // MARK: TitleAccumulator priority chain

    private func consumeAll(_ jsonLines: [String]) throws -> TitleAccumulator {
        var accumulator = TitleAccumulator()
        for line in jsonLines {
            accumulator.consume(try TranscriptDecoder.decode(Data(line.utf8)))
        }
        return accumulator
    }

    private let promptLine = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"first real synthetic prompt about wombats"}}"#
    private let summaryLine = #"{"type":"summary","summary":"Legacy summary title"}"#
    private let aiTitleLine = #"{"type":"ai-title","aiTitle":"Synthetic AI title","sessionId":"s"}"#
    private let customTitleLine = #"{"type":"custom-title","customTitle":"Synthetic custom title","sessionId":"s"}"#

    func testCustomTitleBeatsEverything() throws {
        let acc = try consumeAll([promptLine, summaryLine, aiTitleLine, customTitleLine])
        XCTAssertEqual(acc.best, "Synthetic custom title")
    }

    func testAITitleBeatsSummaryAndPrompt() throws {
        let acc = try consumeAll([promptLine, summaryLine, aiTitleLine])
        XCTAssertEqual(acc.best, "Synthetic AI title")
    }

    func testSummaryBeatsPrompt() throws {
        let acc = try consumeAll([promptLine, summaryLine])
        XCTAssertEqual(acc.best, "Legacy summary title")
    }

    func testPromptIsLastResort() throws {
        let acc = try consumeAll([promptLine])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    func testLastTitleWins() throws {
        let renamed = #"{"type":"custom-title","customTitle":"Renamed later","sessionId":"s"}"#
        let acc = try consumeAll([customTitleLine, renamed])
        XCTAssertEqual(acc.best, "Renamed later")
    }

    func testEmptyCustomTitleFallsThrough() throws {
        let empty = #"{"type":"custom-title","customTitle":"","sessionId":"s"}"#
        let acc = try consumeAll([promptLine, empty])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    func testUnusablePromptsAreSkipped() throws {
        let sidechain = #"{"isSidechain":true,"type":"user","message":{"role":"user","content":"subagent noise"}}"#
        let meta = #"{"isSidechain":false,"isMeta":true,"type":"user","message":{"role":"user","content":"meta noise"}}"#
        let compact = #"{"isSidechain":false,"isCompactSummary":true,"type":"user","message":{"role":"user","content":"This session is being continued"}}"#
        let command = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"<command-name>/clear</command-name>"}}"#
        let blank = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"   "}}"#
        let acc = try consumeAll([sidechain, meta, compact, command, blank, promptLine])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    func testFirstUsablePromptSticks() throws {
        let second = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"second prompt"}}"#
        let acc = try consumeAll([promptLine, second])
        XCTAssertEqual(acc.best, "first real synthetic prompt about wombats")
    }

    // MARK: cleaning

    func testCleanTakesFirstLineTrimmedAndCapped() {
        XCTAssertEqual(TitleAccumulator.clean("  hello\nworld  "), "hello")
        XCTAssertNil(TitleAccumulator.clean("   \n  "))
        let long = String(repeating: "x", count: 300)
        XCTAssertEqual(TitleAccumulator.clean(long)?.count, 200)
    }

    // MARK: SessionTitle.derive over fixture files

    func testDeriveOnRealFixtures() throws {
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("real-titled-session.jsonl")),
            "Metal renderer planning review")
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("real-tooluse-session.jsonl")),
            "Auto-updating bundles from GitHub")
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("real-untitled-session.jsonl")),
            "Reply with exactly: pong")
        XCTAssertEqual(
            SessionTitle.derive(fromFileData: try Fixtures.transcriptData("synthetic-edge-cases.jsonl")),
            "Synthetic custom title")
    }

    func testTitleLineBeyondPromptScanWindowIsStillFound() throws {
        // 150 queue-operation filler lines, then a custom-title at the end:
        // the byte filter must still find it past the 100-line prompt window.
        let filler = #"{"type":"queue-operation","operation":"enqueue","sessionId":"s"}"#
        var fileText = Array(repeating: filler, count: 150).joined(separator: "\n")
        fileText += "\n" + #"{"type":"custom-title","customTitle":"Found at the end","sessionId":"s"}"# + "\n"
        XCTAssertEqual(SessionTitle.derive(fromFileData: Data(fileText.utf8)), "Found at the end")
    }

    func testPromptBeyondScanWindowYieldsNil() throws {
        let filler = #"{"type":"queue-operation","operation":"enqueue","sessionId":"s"}"#
        var fileText = Array(repeating: filler, count: 150).joined(separator: "\n")
        fileText += "\n" + promptLine + "\n"
        // Documented cutoff: prompts are only sought in the first 100 lines.
        XCTAssertNil(SessionTitle.derive(fromFileData: Data(fileText.utf8)))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionTitleTests`
Expected: FAIL to compile — `JSONLines`, `TitleAccumulator`, `SessionTitle` don't exist.

- [ ] **Step 3: Write Sources/ClaudeKit/SessionSummary.swift (first half)**

Create the file with this content (Task 6 appends the `SessionSummary` struct and `SessionFileStamp` to the same file):

```swift
import Foundation

/// Iterates newline-separated chunks of a Data buffer without materializing
/// a line array. Blank lines are skipped.
struct JSONLines: Sequence, IteratorProtocol {
    private let data: Data
    private var offset: Data.Index

    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func next() -> Data? {
        while offset < data.endIndex {
            let newline = data[offset...].firstIndex(of: 0x0A) ?? data.endIndex
            let line = data.subdata(in: offset..<newline)
            offset = newline < data.endIndex ? data.index(after: newline) : data.endIndex
            if !line.isEmpty { return line }
        }
        return nil
    }
}

/// Collects title candidates while scanning transcript entries. `best`
/// applies the priority chain: custom title > AI title > legacy summary >
/// first usable human prompt.
struct TitleAccumulator {
    private(set) var customTitle: String?
    private(set) var aiTitle: String?
    private(set) var legacySummary: String?
    private(set) var firstPrompt: String?

    mutating func consume(_ entry: TranscriptEntry) {
        switch entry {
        case .title(let text, let isCustom, _):
            if isCustom { customTitle = text } else { aiTitle = text }
        case .summary(let text, _):
            legacySummary = text
        case .userPrompt(let text, let context, _):
            if firstPrompt == nil, Self.isUsablePrompt(text, context: context) {
                firstPrompt = text
            }
        default:
            break
        }
    }

    var best: String? {
        [customTitle, aiTitle, legacySummary, firstPrompt]
            .compactMap { $0 }
            .compactMap(Self.clean)
            .first
    }

    static func isUsablePrompt(_ text: String, context: LineContext) -> Bool {
        if context.isSidechain || context.isMeta || context.isCompactSummary { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        // <command-name>…, <local-command-caveat>… and other machine-generated
        // prompts all start with "<".
        if trimmed.hasPrefix("<") { return false }
        return true
    }

    /// First line only, trimmed, capped at 200 characters; nil if nothing is left.
    static func clean(_ title: String) -> String? {
        let firstLine = title
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? title
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(200))
    }
}

enum SessionTitle {
    /// Prompts are only sought this deep; title lines are found at any depth.
    static let maxPromptScanLines = 100
    /// Title lines are short; longer lines are never parsed for titles.
    static let maxTitleLineBytes = 4096

    private static let titleKeyPatterns = [
        Data("\"customTitle\"".utf8),
        Data("\"aiTitle\"".utf8),
        Data("\"type\":\"summary\"".utf8),
    ]

    /// Derives a display title from raw file bytes without JSON-parsing every
    /// line: the first `maxPromptScanLines` lines are decoded (first-prompt
    /// fallback), and beyond that only short lines containing a title key.
    static func derive(fromFileData data: Data) -> String? {
        var accumulator = TitleAccumulator()
        var lineIndex = 0
        var lines = JSONLines(data: data)
        while let line = lines.next() {
            lineIndex += 1
            let parseForPrompt = accumulator.firstPrompt == nil && lineIndex <= maxPromptScanLines
            let parseForTitle = line.count <= maxTitleLineBytes && containsTitleKey(line)
            guard parseForPrompt || parseForTitle,
                  let entry = try? TranscriptDecoder.decode(line) else { continue }
            accumulator.consume(entry)
        }
        return accumulator.best
    }

    static func containsTitleKey(_ line: Data) -> Bool {
        titleKeyPatterns.contains { line.range(of: $0) != nil }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SessionTitleTests`
Expected: all 15 tests PASS.

- [ ] **Step 5: Run the full suite, then commit**

Run: `swift test` — all green, then:

```bash
git add Sources/ClaudeKit/SessionSummary.swift Tests/ClaudeKitTests/SessionTitleTests.swift
git commit -m "feat: streaming JSONLines and title derivation with priority chain"
```

---

### Task 6: SessionStore actor — projects(), sessions(in:), transcript(for:)

**Files:**
- Modify: `Sources/ClaudeKit/SessionSummary.swift` (append `SessionSummary` + `SessionFileStamp`)
- Create: `Sources/ClaudeKit/SessionStore.swift`
- Create: `Tests/ClaudeKitTests/SessionStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/SessionStoreTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class SessionStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeProject(_ name: String) throws -> URL {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    private func writeSession(
        _ project: URL, id: String, contents: String, modified: Date? = nil
    ) throws -> URL {
        let url = project.appendingPathComponent("\(id).jsonl")
        try Data(contents.utf8).write(to: url)
        if let modified {
            try FileManager.default.setAttributes(
                [.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    private let promptLine = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"hello from the test corpus"}}"#

    func testProjectsSkipsNonDirectoriesAndSorts() async throws {
        _ = try makeProject("-zeta-project")
        _ = try makeProject("-alpha-project")
        try Data("stray".utf8).write(to: root.appendingPathComponent("stray-file.txt"))
        let store = SessionStore(projectsRoot: root)
        let projects = try await store.projects()
        XCTAssertEqual(projects.map(\.flattenedName), ["-alpha-project", "-zeta-project"])
        // Unresolvable names fall back to the flattened form.
        XCTAssertEqual(projects[0].originalPath, "-alpha-project")
    }

    func testProjectsOnMissingRootReturnsEmpty() async throws {
        let store = SessionStore(projectsRoot: root.appendingPathComponent("does-not-exist"))
        let projects = try await store.projects()
        XCTAssertEqual(projects.count, 0)
    }

    func testSessionsSkipsClutterAndSortsByRecency() async throws {
        let project = try makeProject("-alpha-project")
        // Clutter that must be skipped: memory/, sessions-index.json,
        // a bare-UUID directory, a directory named like a session file.
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("memory"), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: project.appendingPathComponent("sessions-index.json"))
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("0e0e0e0e-1111-2222-3333-444444444444"),
            withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: project.appendingPathComponent("fake-dir.jsonl"), withIntermediateDirectories: true)

        try writeSession(project, id: "older", contents: promptLine + "\n",
                         modified: Date(timeIntervalSince1970: 1_000_000))
        try writeSession(project, id: "newer", contents: promptLine + "\n",
                         modified: Date(timeIntervalSince1970: 2_000_000))

        let store = SessionStore(projectsRoot: root)
        let project0 = try await store.projects()[0]
        let sessions = try await store.sessions(in: project0)
        XCTAssertEqual(sessions.map(\.id), ["newer", "older"])
        XCTAssertEqual(sessions[0].title, "hello from the test corpus")
        XCTAssertEqual(sessions[0].lastActivity, Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(sessions[0].approximateSizeBytes, promptLine.utf8.count + 1)
        XCTAssertEqual(sessions[0].project, project0)
        XCTAssertEqual(sessions[0].fileURL.lastPathComponent, "newer.jsonl")
    }

    func testTitleFallsBackToSessionID() async throws {
        let project = try makeProject("-alpha-project")
        try writeSession(project, id: "empty-session",
                         contents: #"{"type":"mode","mode":"normal","sessionId":"s"}"# + "\n")
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        XCTAssertEqual(sessions[0].title, "empty-session")
    }

    func testFixtureTitlesAndTranscriptCounts() async throws {
        let project = try makeProject("-fixture-project")
        for (id, fixture) in [("titled", "real-titled-session.jsonl"),
                              ("tooluse", "real-tooluse-session.jsonl"),
                              ("untitled", "real-untitled-session.jsonl"),
                              ("synthetic", "synthetic-edge-cases.jsonl")] {
            let data = try Fixtures.transcriptData(fixture)
            try data.write(to: project.appendingPathComponent("\(id).jsonl"))
        }
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        XCTAssertEqual(byID["titled"]?.title, "Metal renderer planning review")
        XCTAssertEqual(byID["tooluse"]?.title, "Auto-updating bundles from GitHub")
        XCTAssertEqual(byID["untitled"]?.title, "Reply with exactly: pong")
        XCTAssertEqual(byID["synthetic"]?.title, "Synthetic custom title")

        XCTAssertEqual(try await store.transcript(for: XCTUnwrap(byID["titled"])).count, 28)
        XCTAssertEqual(try await store.transcript(for: XCTUnwrap(byID["tooluse"])).count, 141)
        XCTAssertEqual(try await store.transcript(for: XCTUnwrap(byID["untitled"])).count, 11)
        XCTAssertEqual(try await store.transcript(for: XCTUnwrap(byID["synthetic"])).count, 22)
    }

    func testTranscriptToleratesMalformedLines() async throws {
        let project = try makeProject("-alpha-project")
        let session = try writeSession(
            project, id: "broken",
            contents: promptLine + "\n" + "this line is not JSON {{{" + "\n")
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        let entries = try await store.transcript(for: sessions[0])
        XCTAssertEqual(entries.count, 2)
        guard case .userPrompt = entries[0] else { return XCTFail("expected prompt first") }
        guard case .unknown(let raw) = entries[1] else { return XCTFail("expected unknown second") }
        XCTAssertEqual(raw.stringValue, "this line is not JSON {{{")
        _ = session
    }

    func testEmptyProjectHasNoSessions() async throws {
        _ = try makeProject("-alpha-project")
        let store = SessionStore(projectsRoot: root)
        let sessions = try await store.sessions(in: try await store.projects()[0])
        XCTAssertEqual(sessions.count, 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionStoreTests`
Expected: FAIL to compile — `SessionStore`, `SessionSummary` don't exist.

- [ ] **Step 3: Append to Sources/ClaudeKit/SessionSummary.swift**

Add at the end of the file:

```swift
/// One session file on disk, cheaply summarized for list display.
public struct SessionSummary: Sendable, Identifiable {
    /// Session UUID (the filename stem).
    public let id: String
    public let project: ProjectFolder
    public let fileURL: URL
    /// Custom title > AI title > legacy summary > first prompt > session id.
    public let title: String
    /// File modification time.
    public let lastActivity: Date
    public let approximateSizeBytes: Int

    public init(
        id: String, project: ProjectFolder, fileURL: URL,
        title: String, lastActivity: Date, approximateSizeBytes: Int
    ) {
        self.id = id
        self.project = project
        self.fileURL = fileURL
        self.title = title
        self.lastActivity = lastActivity
        self.approximateSizeBytes = approximateSizeBytes
    }
}

/// Enumeration record for one session file: everything list/index code needs
/// without opening the file. Internal — SearchIndex and the watcher use it
/// to avoid paying title derivation on every pass.
struct SessionFileStamp: Sendable {
    let url: URL
    let sessionID: String
    let modified: Date
    let size: Int
}
```

- [ ] **Step 4: Write Sources/ClaudeKit/SessionStore.swift**

```swift
import Foundation

/// Read-only view over `~/.claude/projects`: project folders, session
/// summaries, full transcripts, and (Task 10) a change stream. No CLI
/// processes are involved anywhere in this type.
public actor SessionStore {
    public let projectsRoot: URL
    let pollInterval: Duration

    /// De-flattening is filesystem-search; cache folders by name so repeated
    /// enumeration (rescans, reindexes) doesn't redo it.
    private var projectCache: [String: ProjectFolder] = [:]

    public init(
        projectsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects"),
        pollInterval: Duration = .seconds(2)
    ) {
        self.projectsRoot = projectsRoot
        self.pollInterval = pollInterval
    }

    /// Project folders sorted by flattened name. A missing root is an empty
    /// store, not an error (fresh machines have no ~/.claude/projects).
    public func projects() throws -> [ProjectFolder] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: projectsRoot.path) else { return [] }
        let contents = try fileManager.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map { url in
                let name = url.lastPathComponent
                if let cached = projectCache[name], cached.directoryURL == url {
                    return cached
                }
                let folder = ProjectFolder(directoryURL: url)
                projectCache[name] = folder
                return folder
            }
            .sorted { $0.flattenedName < $1.flattenedName }
    }

    /// Session summaries for one project, newest first. Title derivation
    /// scans each file's bytes (see SessionTitle) — cheap for typical files,
    /// measured by the Task 11 gate for the pathological ones.
    public func sessions(in project: ProjectFolder) throws -> [SessionSummary] {
        try sessionFileStamps(in: project)
            .map { stamp in
                let title = (try? Data(contentsOf: stamp.url, options: .mappedIfSafe))
                    .flatMap(SessionTitle.derive(fromFileData:))
                return SessionSummary(
                    id: stamp.sessionID,
                    project: project,
                    fileURL: stamp.url,
                    title: title ?? stamp.sessionID,
                    lastActivity: stamp.modified,
                    approximateSizeBytes: stamp.size)
            }
            .sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Full decode of one session file. Malformed lines (e.g. a torn write
    /// at the tail) surface as `.unknown` with the raw text, never an error.
    public func transcript(for session: SessionSummary) throws -> [TranscriptEntry] {
        let data = try Data(contentsOf: session.fileURL, options: .mappedIfSafe)
        var entries: [TranscriptEntry] = []
        for line in JSONLines(data: data) {
            if let entry = try? TranscriptDecoder.decode(line) {
                entries.append(entry)
            } else {
                entries.append(.unknown(raw: .string(String(decoding: line, as: UTF8.self))))
            }
        }
        return entries
    }

    /// Stat-only enumeration of a project's session files (depth 2,
    /// `*.jsonl` regular files only). Shared by sessions(in:), the search
    /// indexer, and the change watcher.
    func sessionFileStamps(in project: ProjectFolder) throws -> [SessionFileStamp] {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let contents = try fileManager.contentsOfDirectory(
            at: project.directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles])
        var stamps: [SessionFileStamp] = []
        for url in contents where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { continue }
            stamps.append(SessionFileStamp(
                url: url,
                sessionID: url.deletingPathExtension().lastPathComponent,
                modified: values.contentModificationDate ?? .distantPast,
                size: values.fileSize ?? 0))
        }
        return stamps
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SessionStoreTests`
Expected: all 7 tests PASS.

- [ ] **Step 6: Run the full suite, then commit**

Run: `swift test` — all green, then:

```bash
git add Sources/ClaudeKit/SessionSummary.swift Sources/ClaudeKit/SessionStore.swift Tests/ClaudeKitTests/SessionStoreTests.swift
git commit -m "feat: SessionStore enumeration, titles, and tolerant transcript loading"
```

---

### Task 7: SQLiteDatabase — minimal system-SQLite wrapper

Internal (not public API). Owned and confined by the `SearchIndex` actor; the wrapper itself makes no thread-safety promises.

**Files:**
- Create: `Sources/ClaudeKit/SQLiteDatabase.swift`
- Create: `Tests/ClaudeKitTests/SQLiteDatabaseTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/SQLiteDatabaseTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class SQLiteDatabaseTests: XCTestCase {

    private func makeDB() throws -> SQLiteDatabase {
        try SQLiteDatabase(path: ":memory:")
    }

    func testExecPrepareBindStepRoundTrip() throws {
        let db = try makeDB()
        try db.exec("CREATE TABLE t(name TEXT, count INTEGER, ratio REAL, blobless TEXT)")
        let insert = try db.prepare("INSERT INTO t(name, count, ratio, blobless) VALUES(?, ?, ?, ?)")
        try insert.bind(1, "wombat")
        try insert.bind(2, Int64(42))
        try insert.bind(3, 0.5)
        try insert.bindNull(4)
        XCTAssertFalse(try insert.step()) // DONE, no row

        let select = try db.prepare("SELECT name, count, ratio, blobless FROM t")
        XCTAssertTrue(try select.step())
        XCTAssertEqual(select.columnText(0), "wombat")
        XCTAssertEqual(select.columnInt64(1), 42)
        XCTAssertEqual(select.columnDouble(2), 0.5)
        XCTAssertTrue(select.columnIsNull(3))
        XCTAssertFalse(try select.step())
    }

    func testResetAndRebind() throws {
        let db = try makeDB()
        try db.exec("CREATE TABLE t(v TEXT)")
        let insert = try db.prepare("INSERT INTO t(v) VALUES(?)")
        for value in ["a", "b"] {
            try insert.reset()
            try insert.bind(1, value)
            try insert.step()
        }
        let count = try db.prepare("SELECT COUNT(*) FROM t")
        XCTAssertTrue(try count.step())
        XCTAssertEqual(count.columnInt64(0), 2)
    }

    func testLastInsertRowID() throws {
        let db = try makeDB()
        try db.exec("CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)")
        try db.exec("INSERT INTO t(v) VALUES('x')")
        XCTAssertEqual(db.lastInsertRowID, 1)
        try db.exec("INSERT INTO t(v) VALUES('y')")
        XCTAssertEqual(db.lastInsertRowID, 2)
    }

    func testInvalidSQLThrowsWithMessage() throws {
        let db = try makeDB()
        XCTAssertThrowsError(try db.exec("NOT REAL SQL")) { error in
            guard let sqliteError = error as? SQLiteError else { return XCTFail() }
            XCTAssertFalse(sqliteError.message.isEmpty)
        }
        XCTAssertThrowsError(try db.prepare("SELECT * FROM missing_table"))
    }

    func testFileBackedDatabasePersists() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-sqlite-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let db = try SQLiteDatabase(path: path)
            try db.exec("CREATE TABLE t(v TEXT); INSERT INTO t(v) VALUES('persisted')")
        }
        let reopened = try SQLiteDatabase(path: path)
        let select = try reopened.prepare("SELECT v FROM t")
        XCTAssertTrue(try select.step())
        XCTAssertEqual(select.columnText(0), "persisted")
    }

    /// Guards the plan's core assumption: the macOS system SQLite has FTS5,
    /// supports explicit-rowid inserts, rowid range deletes, MATCH + snippet.
    func testFTS5EndToEnd() throws {
        let db = try makeDB()
        try db.exec("CREATE VIRTUAL TABLE lines USING fts5(text, tokenize='unicode61 remove_diacritics 2')")
        let insert = try db.prepare("INSERT INTO lines(rowid, text) VALUES(?, ?)")
        let rows: [(Int64, String)] = [
            ((1 << 32) | 1, "the quick brown fox"),
            ((1 << 32) | 2, "jumped over the lazy dog"),
            ((2 << 32) | 1, "a fox in another file"),
        ]
        for (rowid, text) in rows {
            try insert.reset()
            try insert.bind(1, rowid)
            try insert.bind(2, text)
            try insert.step()
        }

        let search = try db.prepare("""
            SELECT rowid, snippet(lines, 0, '[', ']', '…', 8)
            FROM lines WHERE lines MATCH ? ORDER BY rank
            """)
        try search.bind(1, "fox")
        var hits: [(Int64, String)] = []
        while try search.step() {
            hits.append((search.columnInt64(0), search.columnText(1)))
        }
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.1.contains("[fox]") })

        // Range-delete file 1's rows, as the incremental indexer will.
        let delete = try db.prepare("DELETE FROM lines WHERE rowid >= ? AND rowid < ?")
        try delete.bind(1, Int64(1) << 32)
        try delete.bind(2, Int64(2) << 32)
        try delete.step()

        try search.reset()
        try search.bind(1, "fox")
        var remaining: [Int64] = []
        while try search.step() { remaining.append(search.columnInt64(0)) }
        XCTAssertEqual(remaining, [(2 << 32) | 1])
    }

    func testFTS5PrefixQuery() throws {
        let db = try makeDB()
        try db.exec("CREATE VIRTUAL TABLE lines USING fts5(text)")
        try db.exec("INSERT INTO lines(rowid, text) VALUES(1, 'Auto-updating bundles from GitHub')")
        let search = try db.prepare("SELECT rowid FROM lines WHERE lines MATCH ?")
        try search.bind(1, "\"auto\"*")
        XCTAssertTrue(try search.step())
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SQLiteDatabaseTests`
Expected: FAIL to compile — `SQLiteDatabase` doesn't exist.

- [ ] **Step 3: Write Sources/ClaudeKit/SQLiteDatabase.swift**

```swift
import Foundation
import SQLite3

/// sqlite3_bind_text needs a destructor sentinel telling SQLite to copy the
/// buffer; the C macro SQLITE_TRANSIENT (-1) doesn't import into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteError: Error, Sendable, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// Minimal wrapper over the system SQLite3 C API — open/exec/prepare/bind/
/// step/columns, nothing else. NOT thread-safe: confine each instance to a
/// single actor (SearchIndex owns one). Internal by design; the public
/// surface of ClaudeKit is SearchIndex.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close_v2(db)
            throw SQLiteError(code: SQLITE_CANTOPEN, message: message)
        }
        self.handle = db
    }

    deinit {
        // close_v2 defers the close until outstanding statements finalize,
        // so Statement deinit order doesn't matter.
        sqlite3_close_v2(handle)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(errorMessage)
            throw SQLiteError(code: sqlite3_errcode(handle), message: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteError(
                code: sqlite3_errcode(handle),
                message: String(cString: sqlite3_errmsg(handle)))
        }
        return Statement(statement: statement, database: handle)
    }

    final class Statement {
        private let statement: OpaquePointer
        private let database: OpaquePointer?

        init(statement: OpaquePointer, database: OpaquePointer?) {
            self.statement = statement
            self.database = database
        }

        deinit { sqlite3_finalize(statement) }

        private func check(_ code: Int32) throws {
            guard code == SQLITE_OK else {
                throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
            }
        }

        func bind(_ index: Int32, _ value: String) throws {
            try check(sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT))
        }
        func bind(_ index: Int32, _ value: Int64) throws {
            try check(sqlite3_bind_int64(statement, index, value))
        }
        func bind(_ index: Int32, _ value: Double) throws {
            try check(sqlite3_bind_double(statement, index, value))
        }
        func bindNull(_ index: Int32) throws {
            try check(sqlite3_bind_null(statement, index))
        }

        /// Advances one row. Returns true while a row is available, false at DONE.
        @discardableResult
        func step() throws -> Bool {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            case let code:
                throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
            }
        }

        /// Rewinds for re-execution. Bindings survive a reset — rebind anyway
        /// when looping, for clarity.
        func reset() throws {
            try check(sqlite3_reset(statement))
        }

        func columnText(_ index: Int32) -> String {
            sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        }
        func columnInt64(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }
        func columnDouble(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }
        func columnIsNull(_ index: Int32) -> Bool {
            sqlite3_column_type(statement, index) == SQLITE_NULL
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SQLiteDatabaseTests`
Expected: all 7 tests PASS. If `testFTS5EndToEnd` fails at table creation, STOP and report — that would mean the system SQLite lacks FTS5, which invalidates the search design (it should not happen on macOS 15).

- [ ] **Step 5: Run the full suite, then commit**

Run: `swift test` — all green, then:

```bash
git add Sources/ClaudeKit/SQLiteDatabase.swift Tests/ClaudeKitTests/SQLiteDatabaseTests.swift
git commit -m "feat: minimal system-SQLite wrapper with FTS5 guard tests"
```

---

### Task 8: SearchIndex — schema + incremental reindex

**Files:**
- Create: `Sources/ClaudeKit/SearchIndex.swift`
- Create: `Tests/ClaudeKitTests/SearchIndexTests.swift`

**Design (from the contract amendments):** `files(id, path UNIQUE, session_id, project, mtime, size, title)` + `lines` FTS5 table where `rowid = (file_id << 32) | line_no`. Unchanged `(mtime, size)` → file skipped. Changed → range-delete its rows, reinsert. Vanished → removed. `reindex()` returns the number of files (re)indexed.

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/SearchIndexTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class SearchIndexTests: XCTestCase {
    private var root: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("-test-project"), withIntermediateDirectories: true)
        databaseURL = root.appendingPathComponent("index.sqlite")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var projectDir: URL { root.appendingPathComponent("-test-project") }

    /// Two indexable lines: one prompt, one assistant reply.
    private let quokkaSession = """
    {"isSidechain":false,"type":"user","message":{"role":"user","content":"quokka feeding schedule please"}}
    {"isSidechain":false,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"quokkas eat leaves at dawn"}]}}
    {"type":"mode","mode":"normal","sessionId":"s"}
    """

    private func writeQuokkaSession(id: String = "quokka") throws -> URL {
        let url = projectDir.appendingPathComponent("\(id).jsonl")
        try Data((quokkaSession + "\n").utf8).write(to: url)
        return url
    }

    private func makeStoreAndIndex() throws -> (SessionStore, SearchIndex) {
        let store = SessionStore(projectsRoot: root)
        let index = try SearchIndex(databaseURL: databaseURL, store: store)
        return (store, index)
    }

    func testColdIndexCountsFilesAndLines() async throws {
        // synthetic-edge-cases has exactly 7 indexable lines (3 usable-for-
        // index prompts incl. the compact summary, 1 assistant, 2 titles,
        // 1 legacy summary); the quokka session has 2.
        try Fixtures.transcriptData("synthetic-edge-cases.jsonl")
            .write(to: projectDir.appendingPathComponent("synthetic.jsonl"))
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()

        let reindexed = try await index.reindex()
        XCTAssertEqual(reindexed, 2)
        XCTAssertEqual(try await index.indexedFileCount(), 2)
        XCTAssertEqual(try await index.indexedLineCount(), 9)
        let title = try await index.indexedTitle(forSessionID: "synthetic")
        XCTAssertEqual(title, "Synthetic custom title")
    }

    func testReindexSkipsUnchangedFiles() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        XCTAssertEqual(try await index.reindex(), 1)
        XCTAssertEqual(try await index.reindex(), 0, "unchanged file must be skipped")
        XCTAssertEqual(try await index.indexedLineCount(), 2)
    }

    func testChangedFileIsReindexedNotDuplicated() async throws {
        let url = try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()

        let extra = #"{"isSidechain":false,"type":"user","message":{"role":"user","content":"also a wombat question"}}"#
        try Data((quokkaSession + "\n" + extra + "\n").utf8).write(to: url)
        // Force a clearly different mtime in case the two writes land within
        // filesystem timestamp resolution.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)

        XCTAssertEqual(try await index.reindex(), 1)
        XCTAssertEqual(try await index.indexedFileCount(), 1)
        XCTAssertEqual(try await index.indexedLineCount(), 3, "old rows must be replaced, not accumulated")
    }

    func testDeletedFileIsRemovedFromIndex() async throws {
        let keep = try writeQuokkaSession(id: "keep")
        let drop = try writeQuokkaSession(id: "drop")
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        XCTAssertEqual(try await index.indexedFileCount(), 2)
        XCTAssertEqual(try await index.indexedLineCount(), 4)

        try FileManager.default.removeItem(at: drop)
        XCTAssertEqual(try await index.reindex(), 0)
        XCTAssertEqual(try await index.indexedFileCount(), 1)
        XCTAssertEqual(try await index.indexedLineCount(), 2)
        _ = keep
    }

    func testNewProjectDirectoryIsPickedUp() async throws {
        let (_, index) = try makeStoreAndIndex()
        XCTAssertEqual(try await index.reindex(), 0)
        let newProject = root.appendingPathComponent("-late-project")
        try FileManager.default.createDirectory(at: newProject, withIntermediateDirectories: true)
        try Data((quokkaSession + "\n").utf8)
            .write(to: newProject.appendingPathComponent("late.jsonl"))
        XCTAssertEqual(try await index.reindex(), 1)
        XCTAssertEqual(try await index.indexedFileCount(), 1)
    }

    func testSidechainAndMetaLinesAreNotIndexed() async throws {
        let noise = """
        {"isSidechain":true,"type":"user","message":{"role":"user","content":"sidechain capybara"}}
        {"isSidechain":true,"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"sidechain reply capybara"}]}}
        {"isSidechain":false,"isMeta":true,"type":"user","message":{"role":"user","content":"meta capybara"}}
        """
        try Data((noise + "\n").utf8).write(to: projectDir.appendingPathComponent("noise.jsonl"))
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        XCTAssertEqual(try await index.indexedLineCount(), 0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SearchIndexTests`
Expected: FAIL to compile — `SearchIndex` doesn't exist.

- [ ] **Step 3: Write Sources/ClaudeKit/SearchIndex.swift**

```swift
import Foundation

/// Full-text index over every main session file, incremental by
/// (path, mtime, size). SQLite FTS5 via the system library; the database
/// lives wherever the app points `databaseURL` (Fabled will use
/// ~/Library/Application Support/Fabled/index.sqlite).
public actor SearchIndex {
    private let db: SQLiteDatabase
    private let store: SessionStore

    public init(databaseURL: URL, store: SessionStore) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        self.db = try SQLiteDatabase(path: databaseURL.path)
        self.store = store
        try db.exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS files(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL UNIQUE,
                session_id TEXT NOT NULL,
                project TEXT NOT NULL,
                mtime REAL NOT NULL,
                size INTEGER NOT NULL,
                title TEXT
            );
            CREATE VIRTUAL TABLE IF NOT EXISTS lines
                USING fts5(text, tokenize='unicode61 remove_diacritics 2');
            """)
    }

    private struct KnownFile {
        let id: Int64
        let mtime: Double
        let size: Int64
    }

    /// Walks every project; parses only files whose (mtime, size) changed;
    /// drops index rows for files that vanished. Returns the number of
    /// files (re)parsed — 0 on a warm no-change pass.
    @discardableResult
    public func reindex() async throws -> Int {
        var known: [String: KnownFile] = [:]
        let select = try db.prepare("SELECT id, path, mtime, size FROM files")
        while try select.step() {
            known[select.columnText(1)] = KnownFile(
                id: select.columnInt64(0),
                mtime: select.columnDouble(2),
                size: select.columnInt64(3))
        }

        var seen = Set<String>()
        var reindexed = 0
        for project in try await store.projects() {
            for stamp in try await store.sessionFileStamps(in: project) {
                let path = stamp.url.path
                seen.insert(path)
                let mtime = stamp.modified.timeIntervalSince1970
                if let existing = known[path],
                   existing.mtime == mtime, existing.size == Int64(stamp.size) {
                    continue
                }
                try indexFile(stamp, project: project, replacing: known[path]?.id)
                reindexed += 1
            }
        }
        for (path, file) in known where !seen.contains(path) {
            try remove(fileID: file.id)
        }
        return reindexed
    }

    private func indexFile(
        _ stamp: SessionFileStamp, project: ProjectFolder, replacing existingID: Int64?
    ) throws {
        let data = try Data(contentsOf: stamp.url, options: .mappedIfSafe)
        try db.exec("BEGIN IMMEDIATE")
        do {
            let fileID: Int64
            if let existingID {
                try deleteLines(fileID: existingID)
                let update = try db.prepare("UPDATE files SET mtime = ?, size = ? WHERE id = ?")
                try update.bind(1, stamp.modified.timeIntervalSince1970)
                try update.bind(2, Int64(stamp.size))
                try update.bind(3, existingID)
                try update.step()
                fileID = existingID
            } else {
                let insert = try db.prepare("""
                    INSERT INTO files(path, session_id, project, mtime, size)
                    VALUES(?, ?, ?, ?, ?)
                    """)
                try insert.bind(1, stamp.url.path)
                try insert.bind(2, stamp.sessionID)
                try insert.bind(3, project.flattenedName)
                try insert.bind(4, stamp.modified.timeIntervalSince1970)
                try insert.bind(5, Int64(stamp.size))
                try insert.step()
                fileID = db.lastInsertRowID
            }

            var accumulator = TitleAccumulator()
            var lineNumber: Int64 = 0
            let insertLine = try db.prepare("INSERT INTO lines(rowid, text) VALUES(?, ?)")
            for line in JSONLines(data: data) {
                lineNumber += 1
                guard let entry = try? TranscriptDecoder.decode(line) else { continue }
                accumulator.consume(entry)
                guard let text = Self.indexableText(from: entry) else { continue }
                try insertLine.reset()
                try insertLine.bind(1, (fileID << 32) | lineNumber)
                try insertLine.bind(2, text)
                try insertLine.step()
            }

            let updateTitle = try db.prepare("UPDATE files SET title = ? WHERE id = ?")
            if let title = accumulator.best {
                try updateTitle.bind(1, title)
            } else {
                try updateTitle.bindNull(1)
            }
            try updateTitle.bind(2, fileID)
            try updateTitle.step()

            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    private func deleteLines(fileID: Int64) throws {
        let delete = try db.prepare("DELETE FROM lines WHERE rowid >= ? AND rowid < ?")
        try delete.bind(1, fileID << 32)
        try delete.bind(2, (fileID + 1) << 32)
        try delete.step()
    }

    private func remove(fileID: Int64) throws {
        try db.exec("BEGIN IMMEDIATE")
        do {
            try deleteLines(fileID: fileID)
            let delete = try db.prepare("DELETE FROM files WHERE id = ?")
            try delete.bind(1, fileID)
            try delete.step()
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
    }

    /// Human-relevant text only: non-sidechain prompts (compaction summaries
    /// count — they summarize the session), non-sidechain assistant text,
    /// titles, legacy summaries. Tool results, sidechain traffic, and
    /// bookkeeping lines are never indexed.
    static func indexableText(from entry: TranscriptEntry) -> String? {
        func nonEmpty(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        switch entry {
        case .userPrompt(let text, let context, _):
            guard !context.isSidechain, !context.isMeta else { return nil }
            return nonEmpty(text)
        case .event(.assistant(let message), let context):
            guard !context.isSidechain else { return nil }
            let text = message.content
                .compactMap { block -> String? in
                    if case .text(let blockText) = block { return blockText }
                    return nil
                }
                .joined(separator: "\n")
            return nonEmpty(text)
        case .title(let text, _, _), .summary(let text, _):
            return nonEmpty(text)
        default:
            return nil
        }
    }

    // MARK: test hooks (internal)

    func indexedFileCount() throws -> Int {
        let statement = try db.prepare("SELECT COUNT(*) FROM files")
        _ = try statement.step()
        return Int(statement.columnInt64(0))
    }

    func indexedLineCount() throws -> Int {
        let statement = try db.prepare("SELECT COUNT(*) FROM lines")
        _ = try statement.step()
        return Int(statement.columnInt64(0))
    }

    func indexedTitle(forSessionID sessionID: String) throws -> String? {
        let statement = try db.prepare("SELECT title FROM files WHERE session_id = ?")
        try statement.bind(1, sessionID)
        guard try statement.step() else { return nil }
        return statement.columnIsNull(0) ? nil : statement.columnText(0)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SearchIndexTests`
Expected: all 6 tests PASS.

- [ ] **Step 5: Run the full suite, then commit**

Run: `swift test` — all green, then:

```bash
git add Sources/ClaudeKit/SearchIndex.swift Tests/ClaudeKitTests/SearchIndexTests.swift
git commit -m "feat: SearchIndex with incremental (mtime,size) reindex over FTS5"
```

---

### Task 9: SearchIndex.search() + SearchHit

**Files:**
- Modify: `Sources/ClaudeKit/SearchIndex.swift`
- Modify: `Tests/ClaudeKitTests/SearchIndexTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeKitTests/SearchIndexTests.swift` (inside the class):

```swift
    // MARK: search (Task 9)

    func testSearchFindsPromptAndAssistantLines() async throws {
        try Fixtures.transcriptData("synthetic-edge-cases.jsonl")
            .write(to: projectDir.appendingPathComponent("synthetic.jsonl"))
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()

        // "wombats" appears on line 6 (prompt) and line 9 (assistant reply).
        let hits = try await index.search("wombats", limit: 10)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(Set(hits.map(\.lineNumber)), [6, 9])
        for hit in hits {
            XCTAssertTrue(hit.snippet.contains("[wombats]"), "snippet: \(hit.snippet)")
            XCTAssertEqual(hit.session.id, "synthetic")
            XCTAssertEqual(hit.session.title, "Synthetic custom title")
            XCTAssertEqual(hit.session.project.flattenedName, "-test-project")
            XCTAssertEqual(hit.session.fileURL.lastPathComponent, "synthetic.jsonl")
            XCTAssertEqual(hit.id, "synthetic:\(hit.lineNumber)")
        }
    }

    func testSearchPrefixMatchesLastToken() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        let hits = try await index.search("quok", limit: 10)
        XCTAssertEqual(hits.count, 2, "prefix star on the final token")
    }

    func testSearchMultiTokenIsImplicitAnd() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        XCTAssertEqual(try await index.search("feeding quokka", limit: 10).count, 1)
        XCTAssertEqual(try await index.search("feeding nonexistentword", limit: 10).count, 0)
    }

    func testSearchRespectsLimit() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        XCTAssertEqual(try await index.search("quokka", limit: 1).count, 1)
    }

    func testHostileQueriesDoNotThrow() async throws {
        try writeQuokkaSession()
        let (_, index) = try makeStoreAndIndex()
        _ = try await index.reindex()
        for query in ["\"unbalanced AND (", "NOT", "a* b* OR", "\"\"\"", "   "] {
            _ = try await index.search(query, limit: 10) // must not throw
        }
        XCTAssertEqual(try await index.search("", limit: 10).count, 0)
    }

    func testFTSQuerySanitizer() {
        XCTAssertEqual(SearchIndex.ftsQuery(from: "hello world"), "\"hello\" \"world\"*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "one"), "\"one\"*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: "  spaced   out  "), "\"spaced\" \"out\"*")
        XCTAssertEqual(SearchIndex.ftsQuery(from: #"say "hi""#), #""say" ""hi""*"#)
        XCTAssertEqual(SearchIndex.ftsQuery(from: ""), "")
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SearchIndexTests`
Expected: FAIL to compile — no `search`, no `ftsQuery`, no `SearchHit`.

- [ ] **Step 3: Add SearchHit and search() to Sources/ClaudeKit/SearchIndex.swift**

Add the struct above the actor:

```swift
/// One full-text match. `lineNumber` is 1-based within the session file, so
/// the UI can jump straight to the matching transcript entry.
public struct SearchHit: Sendable, Identifiable {
    /// "\(session.id):\(lineNumber)"
    public let id: String
    public let session: SessionSummary
    /// FTS5 snippet with [ ] markers around matched terms.
    public let snippet: String
    public let lineNumber: Int

    public init(id: String, session: SessionSummary, snippet: String, lineNumber: Int) {
        self.id = id
        self.session = session
        self.snippet = snippet
        self.lineNumber = lineNumber
    }
}
```

Add inside the actor (after `reindex()`):

```swift
    /// Ranked full-text search. Hits are built entirely from index rows —
    /// no session files are opened, so search stays fast even when hits
    /// land in 50 MB transcripts.
    public func search(_ query: String, limit: Int) async throws -> [SearchHit] {
        let match = Self.ftsQuery(from: query)
        guard !match.isEmpty, limit > 0 else { return [] }
        let projectsByName = Dictionary(
            uniqueKeysWithValues: try await store.projects().map { ($0.flattenedName, $0) })

        let statement = try db.prepare("""
            SELECT files.path, files.session_id, files.project, files.mtime,
                   files.size, files.title, lines.rowid,
                   snippet(lines, 0, '[', ']', '…', 16)
            FROM lines
            JOIN files ON files.id = (lines.rowid >> 32)
            WHERE lines MATCH ?
            ORDER BY rank
            LIMIT ?
            """)
        try statement.bind(1, match)
        try statement.bind(2, Int64(limit))

        var hits: [SearchHit] = []
        while try statement.step() {
            let path = statement.columnText(0)
            let sessionID = statement.columnText(1)
            let projectName = statement.columnText(2)
            let fileURL = URL(fileURLWithPath: path)
            let project = projectsByName[projectName] ?? ProjectFolder(
                flattenedName: projectName,
                originalPath: projectName,
                directoryURL: fileURL.deletingLastPathComponent())
            let lineNumber = Int(statement.columnInt64(6) & 0xFFFF_FFFF)
            let session = SessionSummary(
                id: sessionID,
                project: project,
                fileURL: fileURL,
                title: statement.columnIsNull(5) ? sessionID : statement.columnText(5),
                lastActivity: Date(timeIntervalSince1970: statement.columnDouble(3)),
                approximateSizeBytes: Int(statement.columnInt64(4)))
            hits.append(SearchHit(
                id: "\(sessionID):\(lineNumber)",
                session: session,
                snippet: statement.columnText(7),
                lineNumber: lineNumber))
        }
        return hits
    }

    /// Converts free-typed input into a safe FTS5 expression: each
    /// whitespace-separated token becomes a quoted phrase (immune to FTS5
    /// operator syntax), the final one with a prefix star for as-you-type
    /// search. Internal quotes are doubled per SQL quoting rules.
    static func ftsQuery(from userQuery: String) -> String {
        let tokens = userQuery.split(whereSeparator: \.isWhitespace)
        guard !tokens.isEmpty else { return "" }
        return tokens.enumerated().map { offset, token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            let phrase = "\"\(escaped)\""
            return offset == tokens.count - 1 ? phrase + "*" : phrase
        }.joined(separator: " ")
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SearchIndexTests`
Expected: all 12 tests PASS (6 from Task 8 + 6 new).

- [ ] **Step 5: Run the full suite, then commit**

Run: `swift test` — all green, then:

```bash
git add Sources/ClaudeKit/SearchIndex.swift Tests/ClaudeKitTests/SearchIndexTests.swift
git commit -m "feat: FTS5 search with sanitized queries, snippets, and line-precise hits"
```

---

### Task 10: SessionStore.changes — kqueue + poll watcher with debounce

**Files:**
- Create: `Sources/ClaudeKit/DirectoryWatcher.swift`
- Modify: `Sources/ClaudeKit/SessionStore.swift`
- Create: `Tests/ClaudeKitTests/SessionWatcherTests.swift`

**Design recap:** directory kqueue reacts fast to file create/delete/rename but *cannot* see appends to existing files (POSIX semantics), so a poll on `pollInterval` (2 s default, short in tests) complements it. Both signals funnel into one throttled rescan (≥250 ms spacing) that diffs a `(path → mtime,size)` snapshot and yields changed/added/removed session-file URLs to every subscriber. Watching starts on first `changes` access and stops when the last subscriber cancels.

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/SessionWatcherTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

/// Collects change batches from an AsyncStream on a background task.
private actor BatchCollector {
    private(set) var batches: [[URL]] = []
    func append(_ batch: [URL]) { batches.append(batch) }
    var allURLs: Set<URL> { Set(batches.flatMap { $0 }) }
}

final class SessionWatcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("-watched-project"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var projectDir: URL { root.appendingPathComponent("-watched-project") }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: @escaping () async -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < timeout {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return await condition()
    }

    private func makeStore() -> SessionStore {
        SessionStore(projectsRoot: root, pollInterval: .milliseconds(100))
    }

    func testNewFileAppendAndDeleteAreReported() async throws {
        let store = makeStore()
        let collector = BatchCollector()
        let stream = await store.changes
        let consumer = Task {
            for await batch in stream { await collector.append(batch) }
        }
        defer { consumer.cancel() }

        // 1. New session file appears.
        let sessionURL = projectDir.appendingPathComponent("live-session.jsonl")
        try Data("{\"type\":\"mode\",\"mode\":\"normal\"}\n".utf8).write(to: sessionURL)
        let sawCreate = await waitUntil {
            await collector.allURLs.contains { $0.lastPathComponent == "live-session.jsonl" }
        }
        XCTAssertTrue(sawCreate, "creation not reported")

        // 2. Append to the existing file (only the poll can see this).
        let baseline = await collector.batches.count
        let handle = try FileHandle(forWritingTo: sessionURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"type\":\"mode\",\"mode\":\"plan\"}\n".utf8))
        try handle.close()
        let sawAppend = await waitUntil {
            await collector.batches.count > baseline
                && collector.batches.suffix(from: baseline)
                    .flatMap { $0 }
                    .contains { $0.lastPathComponent == "live-session.jsonl" }
        }
        XCTAssertTrue(sawAppend, "append not reported")

        // 3. Deletion.
        let baseline2 = await collector.batches.count
        try FileManager.default.removeItem(at: sessionURL)
        let sawDelete = await waitUntil {
            await collector.batches.count > baseline2
                && collector.batches.suffix(from: baseline2)
                    .flatMap { $0 }
                    .contains { $0.lastPathComponent == "live-session.jsonl" }
        }
        XCTAssertTrue(sawDelete, "deletion not reported")
    }

    func testNewProjectDirectoryIsWatched() async throws {
        let store = makeStore()
        let collector = BatchCollector()
        let stream = await store.changes
        let consumer = Task {
            for await batch in stream { await collector.append(batch) }
        }
        defer { consumer.cancel() }

        let newProject = root.appendingPathComponent("-brand-new-project")
        try FileManager.default.createDirectory(at: newProject, withIntermediateDirectories: true)
        try Data("{\"type\":\"mode\",\"mode\":\"normal\"}\n".utf8)
            .write(to: newProject.appendingPathComponent("fresh.jsonl"))
        let seen = await waitUntil {
            await collector.allURLs.contains { $0.lastPathComponent == "fresh.jsonl" }
        }
        XCTAssertTrue(seen, "session in new project dir not reported")
    }

    func testNonSessionClutterIsIgnored() async throws {
        let store = makeStore()
        let collector = BatchCollector()
        let stream = await store.changes
        let consumer = Task {
            for await batch in stream { await collector.append(batch) }
        }
        defer { consumer.cancel() }

        try Data("{}".utf8).write(to: projectDir.appendingPathComponent("sessions-index.json"))
        try FileManager.default.createDirectory(
            at: projectDir.appendingPathComponent("memory"), withIntermediateDirectories: true)
        // Give the watcher ample time to (wrongly) report something.
        try await Task.sleep(for: .seconds(1))
        let urls = await collector.allURLs
        XCTAssertTrue(urls.isEmpty, "clutter must not produce change events, got \(urls)")
    }

    func testSubscribersAreReleasedOnCancel() async throws {
        let store = makeStore()
        let streamA = await store.changes
        let streamB = await store.changes
        let consumerA = Task { for await _ in streamA {} }
        let consumerB = Task { for await _ in streamB {} }
        let subscribed = await waitUntil { await store.subscriberCount == 2 }
        XCTAssertTrue(subscribed)

        consumerA.cancel()
        consumerB.cancel()
        let released = await waitUntil { await store.subscriberCount == 0 }
        XCTAssertTrue(released, "cancelled consumers must unsubscribe")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SessionWatcherTests`
Expected: FAIL to compile — `SessionStore` has no `changes`/`subscriberCount`.

- [ ] **Step 3: Write Sources/ClaudeKit/DirectoryWatcher.swift**

```swift
import Foundation

/// kqueue-backed dispatch sources for a set of watched directories.
/// Directory-level kqueue fires on entry create/delete/rename — NOT on
/// appends to existing files — which is why SessionStore pairs this with a
/// cheap mtime poll. Not Sendable: confined to the SessionStore actor.
final class DirectoryWatcher {
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private let queue = DispatchQueue(label: "claudekit.directory-watcher")
    private let onEvent: @Sendable () -> Void

    init(onEvent: @escaping @Sendable () -> Void) {
        self.onEvent = onEvent
    }

    /// Idempotent per path; silently skips paths that can't be opened
    /// (deleted between scan and watch — the poll still covers them).
    func watch(directoryAt path: String) {
        guard sources[path] == nil else { return }
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue)
        let handler = onEvent
        source.setEventHandler { handler() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources[path] = source
    }

    func cancelAll() {
        for source in sources.values { source.cancel() }
        sources.removeAll()
    }

    deinit { cancelAll() }
}
```

- [ ] **Step 4: Add the watcher to Sources/ClaudeKit/SessionStore.swift**

4a. Add stored properties after `private var projectCache…`:

```swift
    // MARK: change watching

    private var subscribers: [UUID: AsyncStream<[URL]>.Continuation] = [:]
    private var watcher: DirectoryWatcher?
    private var pollTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?
    private var snapshot: [String: FileStamp] = [:]

    struct FileStamp: Equatable {
        let mtime: Date
        let size: Int
    }
```

4b. Add the public stream property and the watcher machinery at the end of the actor:

```swift
    /// Fires on any session-file change under projectsRoot (create, append,
    /// delete, rename), throttled to at most one batch per 250 ms. Payload =
    /// affected session file URLs. Each access returns an independent
    /// stream; watching starts on first access and stops when the last
    /// subscriber cancels.
    public var changes: AsyncStream<[URL]> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<[URL]>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        startWatchingIfNeeded()
        return stream
    }

    /// Internal, for tests.
    var subscriberCount: Int { subscribers.count }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty { stopWatching() }
    }

    private func startWatchingIfNeeded() {
        guard watcher == nil else { return }
        snapshot = (try? currentSnapshot()) ?? [:]
        let newWatcher = DirectoryWatcher(onEvent: { [weak self] in
            Task { await self?.scheduleRescan() }
        })
        newWatcher.watch(directoryAt: projectsRoot.path)
        for project in (try? projects()) ?? [] {
            newWatcher.watch(directoryAt: project.directoryURL.path)
        }
        watcher = newWatcher

        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.scheduleRescan()
            }
        }
    }

    private func stopWatching() {
        watcher?.cancelAll()
        watcher = nil
        pollTask?.cancel()
        pollTask = nil
        rescanTask?.cancel()
        rescanTask = nil
    }

    /// Throttle, not restartable debounce: kqueue bursts and poll ticks
    /// coalesce into one rescan at most every 250 ms, and a steady signal
    /// stream can never starve the rescan.
    private func scheduleRescan() {
        guard watcher != nil, rescanTask == nil else { return }
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.performScheduledRescan()
        }
    }

    private func performScheduledRescan() {
        rescanTask = nil
        guard !subscribers.isEmpty else { return }
        let current = (try? currentSnapshot()) ?? snapshot
        var changed: [URL] = []
        for (path, stamp) in current where snapshot[path] != stamp {
            changed.append(URL(fileURLWithPath: path))
        }
        for path in snapshot.keys where current[path] == nil {
            changed.append(URL(fileURLWithPath: path))
        }
        snapshot = current
        // Newly created project directories need their own kqueue source.
        for project in (try? projects()) ?? [] {
            watcher?.watch(directoryAt: project.directoryURL.path)
        }
        guard !changed.isEmpty else { return }
        let batch = changed.sorted { $0.path < $1.path }
        for continuation in subscribers.values {
            continuation.yield(batch)
        }
    }

    private func currentSnapshot() throws -> [String: FileStamp] {
        var result: [String: FileStamp] = [:]
        for project in try projects() {
            for stamp in (try? sessionFileStamps(in: project)) ?? [] {
                result[stamp.url.path] = FileStamp(mtime: stamp.modified, size: stamp.size)
            }
        }
        return result
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SessionWatcherTests`
Expected: all 4 tests PASS. These tests involve real timing; if one is flaky, re-run once — persistent flakiness is a bug to fix (usually a missing `waitUntil` or too-tight timeout), not something to paper over with longer sleeps.

- [ ] **Step 6: Run the full suite (twice, for watcher flakiness), then commit**

Run: `swift test && swift test`
Expected: all green both times, then:

```bash
git add Sources/ClaudeKit/DirectoryWatcher.swift Sources/ClaudeKit/SessionStore.swift Tests/ClaudeKitTests/SessionWatcherTests.swift
git commit -m "feat: SessionStore.changes — kqueue + poll watcher with throttled rescan"
```

---

### Task 11: Performance gate against the real corpus

The spec flags long-transcript performance as a risk item: **measure, don't assume.** This task runs env-gated measurements over Ben's real `~/.claude/projects` (456 MB main sessions, largest file 50.1 MB, measured 2026-07-08) and asserts the brief's gates.

**Gates (from the brief):** cold index < 30 s · warm reindex < 1 s · `transcript(for:)` on the largest file < 500 ms. **Added:** full enumeration (projects + all sessions incl. titles) < 5 s.

**Files:**
- Create: `Tests/ClaudeKitTests/PerformanceGateTests.swift`

- [ ] **Step 1: Write the gate test**

`Tests/ClaudeKitTests/PerformanceGateTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

/// Real-corpus performance gate. Run with:
///   CLAUDEKIT_PERF=1 swift test -c release --filter PerformanceGateTests
/// Reads ~/.claude/projects (no writes); builds a throwaway index in tmp.
final class PerformanceGateTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CLAUDEKIT_PERF"] == "1",
            "set CLAUDEKIT_PERF=1 to run the real-corpus performance gate")
    }

    func testRealCorpusPerformance() async throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.path),
            "no ~/.claude/projects on this machine")
        let store = SessionStore(projectsRoot: root)
        let clock = ContinuousClock()

        // 1. Enumeration: every project, every session, titles included.
        var sessionCount = 0
        var largest: SessionSummary?
        let enumerationTime = try await clock.measure {
            for project in try await store.projects() {
                let sessions = try await store.sessions(in: project)
                sessionCount += sessions.count
                for session in sessions
                where session.approximateSizeBytes > (largest?.approximateSizeBytes ?? 0) {
                    largest = session
                }
            }
        }
        print("PERF enumeration: \(sessionCount) sessions in \(enumerationTime)")

        // 2. Full transcript decode of the largest session file.
        let largestSession = try XCTUnwrap(largest)
        var entryCount = 0
        let transcriptTime = try await clock.measure {
            entryCount = try await store.transcript(for: largestSession).count
        }
        print("PERF transcript: \(largestSession.approximateSizeBytes) bytes, " +
              "\(entryCount) entries in \(transcriptTime)")

        // 3. Cold index build into a throwaway database.
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-perf-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let index = try SearchIndex(databaseURL: databaseURL, store: store)
        var coldCount = 0
        let coldTime = try await clock.measure {
            coldCount = try await index.reindex()
        }
        print("PERF cold index: \(coldCount) files in \(coldTime)")

        // 4. Warm no-change reindex.
        var warmCount = 0
        let warmTime = try await clock.measure {
            warmCount = try await index.reindex()
        }
        print("PERF warm index: \(warmCount) files re-parsed in \(warmTime)")
        XCTAssertEqual(warmCount, 0, "warm pass must skip every unchanged file")

        // 5. A search, for the record (no gate — just printed).
        let searchTime = try await clock.measure {
            let hits = try await index.search("swift", limit: 50)
            print("PERF search: \(hits.count) hits")
        }
        print("PERF search time: \(searchTime)")

        // 6. Unknown-type census across the whole corpus: drift detector,
        // not a gate — new CLI line types are EXPECTED to land in .unknown.
        var unknownTypes: [String: Int] = [:]
        var decodedLines = 0
        for project in try await store.projects() {
            for stamp in try await store.sessionFileStamps(in: project) {
                guard let data = try? Data(contentsOf: stamp.url, options: .mappedIfSafe) else { continue }
                for line in JSONLines(data: data) {
                    decodedLines += 1
                    guard let entry = try? TranscriptDecoder.decode(line) else {
                        unknownTypes["<malformed json>", default: 0] += 1
                        continue
                    }
                    if case .unknown(let raw) = entry {
                        unknownTypes[raw["type"]?.stringValue ?? "<no type>", default: 0] += 1
                    }
                }
            }
        }
        print("PERF census: \(decodedLines) lines, unknown types: \(unknownTypes)")

        // The gates. If one fails: report the printed numbers to the
        // coordinator — do NOT tune constants or weaken assertions yourself.
        XCTAssertLessThan(enumerationTime, .seconds(5), "enumeration gate")
        XCTAssertLessThan(transcriptTime, .milliseconds(500), "transcript gate (spec risk item)")
        XCTAssertLessThan(coldTime, .seconds(30), "cold index gate")
        XCTAssertLessThan(warmTime, .seconds(1), "warm index gate")
    }
}
```

- [ ] **Step 2: Confirm the gate is skipped in normal runs**

Run: `swift test --filter PerformanceGateTests`
Expected: 1 test SKIPPED (env not set). The offline suite must never touch the real home directory.

- [ ] **Step 3: Run the gate for real (release build)**

Run: `CLAUDEKIT_PERF=1 swift test -c release --filter PerformanceGateTests`
Expected: PASS, with all `PERF …` lines printed.

**Paste the full PERF output into your task report** — the coordinator records it in the plan status and FOLLOWUPS. If a gate fails, STOP: report the numbers and wait for a decision (candidate levers, in order: PRAGMA synchronous=OFF during cold build; batching multiple files per transaction; a faster line splitter. Do not reach for them without the numbers first).

Known risk going in: the 500 ms transcript gate on a 50 MB file is the tightest. `JSONValue(parsing:)` (Task 2) exists precisely for this; if it still misses, that is a finding for the coordinator, not a license to optimize blind.

- [ ] **Step 4: Run the full offline suite one last time, then commit**

Run: `swift test`
Expected: everything green, perf test skipped.

```bash
git add Tests/ClaudeKitTests/PerformanceGateTests.swift
git commit -m "test: env-gated real-corpus performance gate with drift census"
```

---

## Completion checklist (coordinator)

- [ ] All 11 tasks checked off, tree clean, `swift test` green.
- [ ] PERF numbers from Task 11 recorded here:

```
(fill in from Task 11 report)
enumeration:
transcript(largest):
cold index:
warm index:
search:
unknown census:
```

- [ ] Unknown-census results triaged: new line types → extend `sessionMetaTypes` or fixtures if warranted, else leave as `.unknown` by design.
- [ ] FOLLOWUPS.md updated with anything deferred from reviews.
- [ ] DECISIONS.md entries for the contract amendments confirmed present (written at plan time).
- [ ] Brief file marked as expanded; this plan's STATUS updated to COMPLETE after merge.

## Self-review notes (plan author, 2026-07-08)

- **Spec coverage:** brief task outline items 1–9 map to Tasks 1–11 (brief item 2 → Tasks 2–3; item 4 → Tasks 5–6; item 6 → Task 8). Locked API implemented: `ProjectFolder`, `SessionSummary`, `TranscriptEntry` (amended, ledgered), `SessionStore` (+`pollInterval`), `SearchHit`, `SearchIndex` (+`reindex` return). Index location `~/Library/Application Support/Fabled/index.sqlite` is the app's choice in Plan 3 — ClaudeKit takes `databaseURL`.
- **Type-consistency pass done:** `SessionFileStamp` (internal) is produced by `SessionStore.sessionFileStamps(in:)` (Task 6) and consumed by `SearchIndex` (Task 8) and the watcher snapshot (Task 10); `TitleAccumulator` is shared by `SessionTitle.derive` (Task 5) and `SearchIndex.indexFile` (Task 8); `JSONValue(parsing:)` (Task 2) is used by `TranscriptDecoder.decode` (Task 3). All census constants trace to the 2026-07-08 probe results recorded above.
- **Known accepted trade-offs:** unicode61 tokenizer is weak for CJK text (revisit with a trigram tokenizer if it ever matters); prompts beyond line 100 yield id-fallback titles; `sessions(in:)` pays a byte-scan per file per call (Plan 3 may cache; the enumeration gate bounds it); FTS5 rowid-range delete performance is asserted by test but only at toy scale — the warm gate covers the real cost.
