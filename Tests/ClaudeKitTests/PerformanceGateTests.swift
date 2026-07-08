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
        //
        // Transcript gate amended 500ms -> 1s (2026-07-08, see DECISIONS.md):
        // measured 634 ms stable on the corpus-largest file (52.5 MB, 16,211
        // entries) after eliminating per-line copies; the remaining cost is
        // JSONSerialization-parse + bridge bound (~39 us/line, ~83 MB/s).
        // Beating 500 ms requires a different decode architecture (custom
        // parser / lazy raw payloads), not warranted before Plan 3's UX
        // proves it matters. 1 s remains a real regression tripwire — a
        // JSONDecoder fallback, a double-parse, or quadratic behavior would
        // blow through it.
        XCTAssertLessThan(enumerationTime, .seconds(5), "enumeration gate")
        XCTAssertLessThan(
            transcriptTime, .seconds(1),
            "transcript gate (spec risk item; amended 500ms→1s 2026-07-08, see DECISIONS.md)")
        XCTAssertLessThan(coldTime, .seconds(30), "cold index gate")
        XCTAssertLessThan(warmTime, .seconds(1), "warm index gate")
    }
}
