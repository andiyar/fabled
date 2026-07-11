import XCTest
import ClaudeKit
@testable import FabledCore

@MainActor
final class ChatSessionTests: XCTestCase {
    private func makeSession()
        -> (ChatSession, AsyncStream<AgentEvent>.Continuation, OutboundRecorder) {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"))
        session.begin()
        return (session, continuation, recorder)
    }

    private func yield(_ continuation: AsyncStream<AgentEvent>.Continuation,
                       _ json: String) throws {
        continuation.yield(try AgentEventDecoder.decode(Data(json.utf8)))
    }

    func testInitCatalogHarvest() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[{"name":"compact","description":"Compact the conversation","argumentHint":""}],"models":[{"value":"default","resolvedModel":"claude-opus-4-8","displayName":"Default (recommended)","description":"Opus"},{"value":"haiku","displayName":"Haiku"}],"output_style":"default"}}}
        """#)
        await waitUntil("catalog") { !session.commands.isEmpty }
        XCTAssertEqual(session.commands.map(\.name), ["compact"])
        XCTAssertEqual(session.models.map(\.value), ["default", "haiku"])
        XCTAssertEqual(session.models[0].displayName, "Default (recommended)")
    }

    func testSystemInitPopulatesModelAndMode() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"init","session_id":"s1","model":"claude-haiku-4-5-20251001","cwd":"/tmp/demo","permissionMode":"default","tools":[],"slash_commands":[],"agents":[],"skills":[],"claude_code_version":"\#(ChatSession.testedCLIVersion)"}
        """#)
        await waitUntil("init") { session.info != nil }
        XCTAssertEqual(session.currentModel, "claude-haiku-4-5-20251001")
        XCTAssertEqual(session.permissionMode, "default")
        XCTAssertNil(session.versionNote, "tested version raises no banner")
    }

    func testVersionNoteOnDrift() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"init","session_id":"s1","model":"m","cwd":"/","permissionMode":"default","tools":[],"slash_commands":[],"agents":[],"skills":[],"claude_code_version":"9.9.9"}
        """#)
        await waitUntil("init") { session.info != nil }
        XCTAssertNotNil(session.versionNote)
    }

    // MARK: - Deferred init (CLI 2.1.205 holds `system init` until first turn)

    func testCatalogMarksReadyAndAdoptsDefaultModel() async throws {
        let (session, continuation, _) = makeSession()
        XCTAssertFalse(session.isReady)
        XCTAssertFalse(session.isAwaitingFirstMessage)
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[],"models":[{"value":"default","resolvedModel":"claude-opus-4-8","displayName":"Default (recommended)"},{"value":"haiku","displayName":"Haiku"}]}}}
        """#)
        await waitUntil("ready") { session.isReady }
        XCTAssertTrue(session.isAwaitingFirstMessage,
                      "ready + no user turn yet = awaiting first message")
        XCTAssertEqual(session.currentModel, "claude-opus-4-8",
                       "no explicit model: adopt the catalog default's resolved id")
    }

    func testCatalogDoesNotOverrideExplicitModel() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"),
            model: "haiku")
        session.begin()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"models":[{"value":"default","resolvedModel":"claude-opus-4-8","displayName":"Default"}]}}}
        """#)
        await waitUntil("ready") { session.isReady }
        XCTAssertEqual(session.currentModel, "haiku")
    }

    func testSendClearsAwaitingFirstMessage() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{}}}
        """#)
        await waitUntil("ready") { session.isReady }
        XCTAssertTrue(session.isAwaitingFirstMessage)
        session.send("hello")
        XCTAssertFalse(session.isAwaitingFirstMessage)
    }

    func testTerminatedAfterReadyIsNotALaunchFailure() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{}}}
        """#)
        await waitUntil("ready") { session.isReady }
        // 2.1.205 defers `system init` until the first user turn, so a session
        // closed before typing dies with info == nil — that is NOT a launch
        // failure once the initialize handshake was acknowledged.
        continuation.yield(.terminated(exitCode: 0))
        continuation.finish()
        await waitUntil("ended") { session.hasEnded }
        XCTAssertNil(session.info)
        XCTAssertNil(session.versionNote,
                     "handshake acked: no dead-at-launch banner")
    }

    func testDiskVersionDriftBannerAndInitAuthority() async throws {
        let (session, continuation, _) = makeSession()
        session.noteDiskVersion(ChatSession.testedCLIVersion)
        XCTAssertNil(session.versionNote, "matching disk version raises no banner")
        session.noteDiskVersion(nil)
        XCTAssertNil(session.versionNote, "unparseable install layout stays quiet")
        session.noteDiskVersion("9.9.9")
        XCTAssertNotNil(session.versionNote, "drifted disk version warns at launch")
        // `system init` (first turn) is authoritative: a matching version
        // clears a stale disk-derived warning.
        try yield(continuation, #"""
        {"type":"system","subtype":"init","session_id":"s1","model":"m","cwd":"/","permissionMode":"default","tools":[],"slash_commands":[],"agents":[],"skills":[],"claude_code_version":"\#(ChatSession.testedCLIVersion)"}
        """#)
        await waitUntil("init") { session.info != nil }
        XCTAssertNil(session.versionNote)
    }

    func testSendEchoesAndTracksTurns() async throws {
        let (session, continuation, recorder) = makeSession()
        session.send("  hello  ")
        XCTAssertTrue(session.isWorking)
        guard case .userMessage(_, "hello") = session.timeline.first else {
            return XCTFail("send must echo the trimmed prompt: \(session.timeline)")
        }
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.send("hello")])

        // A queued second message keeps the session working through the
        // first result (probe finding 6).
        session.send("second")
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.01,"uuid":"r1"}"#)
        await waitUntil("first result") { session.cumulativeCostUSD > 0 }
        XCTAssertTrue(session.isWorking, "one of two turns still in flight")
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"total_cost_usd":0.025,"uuid":"r2"}"#)
        await waitUntil("second result") { !session.isWorking }
        // total_cost_usd is session-cumulative on the wire — assigned, not
        // summed (0.035 here would mean double-counting).
        XCTAssertEqual(session.cumulativeCostUSD, 0.025, accuracy: 0.0001)
    }

    func testCostTracksWireCumulative() async throws {
        let (session, continuation, _) = makeSession()
        // total_cost_usd is SESSION-CUMULATIVE on the wire (slashfx +
        // control-ops fixtures, 2026-07-11): assign, never sum.
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01,"usage":{"input_tokens":100},"uuid":"r1"}"#)
        await waitUntil("first result") { session.cumulativeCostUSD > 0 }
        XCTAssertEqual(session.cumulativeCostUSD, 0.01, accuracy: 0.0001)
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.025,"usage":{"input_tokens":250},"uuid":"r2"}"#)
        await waitUntil("second result") { session.cumulativeCostUSD > 0.02 }
        XCTAssertEqual(session.cumulativeCostUSD, 0.025, accuracy: 0.0001,
                       "cumulative wire value assigned, not summed (0.035 = double-count)")
        XCTAssertEqual(session.lastUsage?["input_tokens"]?.doubleValue, 250)
        // A synthetic slash result (num_turns 0) echoes the cumulative cost
        // unchanged and carries all-zeros usage — neither may clobber state.
        try yield(continuation, #"{"type":"result","subtype":"success","is_error":false,"num_turns":0,"total_cost_usd":0.025,"usage":{"input_tokens":0},"uuid":"r3"}"#)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.cumulativeCostUSD, 0.025, accuracy: 0.0001,
                       "synthetic echo leaves the cumulative value unchanged")
        XCTAssertEqual(session.lastUsage?["input_tokens"]?.doubleValue, 250,
                       "synthetic all-zeros usage must not overwrite the real turn's")
    }

    func testPermissionFlow() async throws {
        let (session, continuation, recorder) = makeSession()
        try yield(continuation, #"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#)
        await waitUntil("pending permission") { session.pendingGate != nil }
        XCTAssertEqual(session.activityState, .needsApproval)
        guard case .permission(let request)? = session.pendingGate else {
            return XCTFail("expected permission gate, got \(String(describing: session.pendingGate))")
        }

        session.respond(to: request, decision: .allowAsRequested)
        XCTAssertNil(session.pendingGate)
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.respond(requestID: "p1", behavior: "allow",
                                          updatedInput: nil, message: nil)])
        let permissionItem = session.timeline.first {
            if case .permission = $0 { return true } else { return false }
        }
        guard case .permission(_, _, let resolution) = permissionItem,
              resolution == .allowAsRequested else {
            return XCTFail("resolution must land in the timeline")
        }
    }

    func testAbortedTurnClearsPendingPermission() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}
        """#)
        await waitUntil("pending permission") { session.pendingGate != nil }
        XCTAssertEqual(session.activityState, .needsApproval)

        // interrupt → error_during_execution abandons the open gate: the CLI
        // is no longer waiting for a decision (fixtures/2026-07-09-interrupt.jsonl).
        try yield(continuation, #"{"type":"result","subtype":"error_during_execution","is_error":true,"uuid":"r1"}"#)
        await waitUntil("gate cleared") { session.pendingGate == nil }
        XCTAssertEqual(session.activityState, .idle)
        let permissionItem = session.timeline.first {
            if case .permission = $0 { return true } else { return false }
        }
        guard case .permission(_, _, let resolution) = permissionItem else {
            return XCTFail("permission card must remain in the timeline")
        }
        XCTAssertNil(resolution, "abandoned gate stays unresolved-historical")
    }

    func testTerminatedEndsSession() async throws {
        let (session, continuation, _) = makeSession()
        continuation.yield(.terminated(exitCode: 0))
        continuation.finish()
        await waitUntil("ended") { session.hasEnded }
        XCTAssertEqual(session.activityState, .ended)
        XCTAssertFalse(session.isWorking)
    }

    func testTerminatedBeforeInitSurfacesLoudBanner() async throws {
        let (session, continuation, _) = makeSession()
        // Child dies with 127 (env exit) before any `system init` arrived.
        continuation.yield(.terminated(exitCode: 127))
        continuation.finish()
        await waitUntil("ended") { session.hasEnded }
        XCTAssertNil(session.info)
        XCTAssertNotNil(session.versionNote, "dead-at-launch must not be silent")
        XCTAssertTrue(session.versionNote?.contains("127") ?? false,
                      "banner names the exit code: \(session.versionNote ?? "nil")")
    }

    func testSeedTimeline() {
        let (session, _, _) = makeSession()
        session.seed(timeline: [.userMessage(id: "m1", text: "old prompt")])
        XCTAssertEqual(session.timeline.count, 1)
        session.seed(timeline: [.userMessage(id: "m2", text: "ignored")])
        XCTAssertEqual(session.timeline.first?.id, "m1",
                       "seed only fills an empty timeline")
    }

    func testTitleFromFirstPrompt() {
        let (session, _, _) = makeSession()
        XCTAssertEqual(session.title, "demo", "falls back to the folder name")
        session.send("Fix the login bug\nplease")
        XCTAssertEqual(session.title, "Fix the login bug")
    }

    private func yieldEvent(_ continuation: AsyncStream<AgentEvent>.Continuation,
                            _ json: String) throws {
        continuation.yield(try AgentEventDecoder.decode(Data(json.utf8)))
    }

    func testQuestionGateAnswerRoundTrip() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"control_request","request_id":"q1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Color?","header":"C","options":[{"label":"Red","description":""},{"label":"Blue","description":""}],"multiSelect":false}]},"requires_user_interaction":true,"tool_use_id":"t9"}}"#)
        await waitUntil("question gate") { session.pendingGates.count == 1 }
        guard case .question(let prompt)? = session.pendingGate else {
            return XCTFail("expected question gate, got \(String(describing: session.pendingGate))")
        }
        XCTAssertEqual(session.activityState, .needsApproval)

        session.answer(prompt, answers: ["Color?": "Blue"])
        let entries = await waitForEntries(recorder, count: 1)
        guard case .respond("q1", "allow", let updated, nil) = entries[0] else {
            return XCTFail("got \(entries)")
        }
        XCTAssertEqual(updated?["answers"]?["Color?"]?.stringValue, "Blue")
        XCTAssertTrue(session.pendingGates.isEmpty)
        XCTAssertTrue(session.timeline.isEmpty, "no permission row for gates")
    }

    func testSkipSendsEchoWithoutAnswers() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"control_request","request_id":"q2","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[{"question":"Color?","header":"C","options":[{"label":"Red","description":""}],"multiSelect":false}]},"requires_user_interaction":true}}"#)
        await waitUntil("gate") { session.pendingGate != nil }
        guard case .question(let prompt)? = session.pendingGate else { return XCTFail() }
        session.skipQuestions(prompt)
        let entries = await waitForEntries(recorder, count: 1)
        guard case .respond("q2", "allow", let updated, nil) = entries[0] else {
            return XCTFail("got \(entries)")
        }
        XCTAssertNil(updated?["answers"], "skip = echo, no answers key (probe finding 3)")
    }

    func testPlanApprovalAndStatusModeSwitch() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"),
                                  permissionMode: "plan")
        session.begin()
        try yieldEvent(continuation,
            ##"{"type":"control_request","request_id":"e1","request":{"subtype":"can_use_tool","tool_name":"ExitPlanMode","input":{"plan":"# The Plan"},"requires_user_interaction":true}}"##)
        await waitUntil("plan gate") { session.pendingGate != nil }
        guard case .planApproval(let approval)? = session.pendingGate else { return XCTFail() }
        XCTAssertEqual(approval.plan, "# The Plan")

        session.approvePlan(approval)
        _ = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(session.permissionMode, "plan", "mode changes only on the CLI's status event")

        try yieldEvent(continuation,
            #"{"type":"system","subtype":"status","status":null,"permissionMode":"default","uuid":"s1"}"#)
        await waitUntil("mode switch") { session.permissionMode == "default" }
    }

    func testPlanRejectionPhrasing() async throws {
        let (connection, continuation, recorder) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            ##"{"type":"control_request","request_id":"e2","request":{"subtype":"can_use_tool","tool_name":"ExitPlanMode","input":{"plan":"# P"},"requires_user_interaction":true}}"##)
        await waitUntil("gate") { session.pendingGate != nil }
        guard case .planApproval(let approval)? = session.pendingGate else { return XCTFail() }
        session.rejectPlan(approval, feedback: "needs a licence section")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .respond("e2", "deny", nil, let message) = entries[0] else {
            return XCTFail("got \(entries)")
        }
        XCTAssertEqual(message,
            "The user rejected the plan with this feedback: needs a licence section")
    }

    func testTodosTrackLatestList() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"td1","name":"TodoWrite","input":{"todos":[{"content":"a","status":"in_progress","activeForm":"a"},{"content":"b","status":"pending","activeForm":"b"}]}}]},"uuid":"a1"}"#)
        await waitUntil("todos") { session.todos.count == 2 }
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"td2","name":"TodoWrite","input":{"todos":[{"content":"a","status":"completed","activeForm":"a"},{"content":"b","status":"completed","activeForm":"b"}]}}]},"uuid":"a2"}"#)
        await waitUntil("todos update") { session.todos.allSatisfy { $0.status == .completed } }
    }

    func testEmptyTodoWriteLeavesTodosUnchanged() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"td1","name":"TodoWrite","input":{"todos":[{"content":"a","status":"pending","activeForm":"a"}]}}]},"uuid":"a1"}"#)
        await waitUntil("todos") { session.todos.count == 1 }
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"td2","name":"TodoWrite","input":{"todos":[]}}]},"uuid":"a2"}"#)
        // Both events fold into the timeline in order; once the second card
        // exists, the empty write has been fully processed.
        await waitUntil("second write processed") { session.timeline.count == 2 }
        XCTAssertEqual(session.todos.count, 1, "empty TodoWrite must not clear todos")
    }

    func testSubagentEventsRouteToSubTimeline() async throws {
        let (connection, continuation, _) = makeFakeConnection()
        let session = ChatSession(connection: connection, workingDirectory: .init(filePath: "/tmp"))
        session.begin()
        // Parent Task call in the main timeline…
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"task-1","name":"Task","input":{"description":"explore"}}]},"uuid":"a1"}"#)
        // …then parented traffic.
        try yieldEvent(continuation,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"sub-t1","name":"Bash","input":{"command":"ls"}}]},"parent_tool_use_id":"task-1","uuid":"a2"}"#)
        try yieldEvent(continuation,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"sub-t1","content":"ok","is_error":false}]},"parent_tool_use_id":"task-1","uuid":"u1"}"#)
        await waitUntil("routing") { session.subagentTimelines["task-1"]?.count == 1 }
        XCTAssertEqual(session.timeline.count, 1, "main timeline holds only the Task card")
        guard case .toolCall("sub-t1", "Bash", _, _, .string("ok"), false, false) =
            session.subagentTimelines["task-1"]![0] else {
            return XCTFail("sub-timeline should reduce normally: \(session.subagentTimelines)")
        }
        XCTAssertFalse(session.isThinking,
                       "subagent stream state must not drive the parent spinner")
    }

    func testCatalogHarvestsEffortMetadata() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[],"models":[{"value":"default","resolvedModel":"claude-opus-4-8[1m]","displayName":"Default (recommended)","supportsEffort":true,"supportedEffortLevels":["low","medium","high","xhigh","max"]},{"value":"haiku","displayName":"Haiku","supportsEffort":false}]}}}
        """#)
        await waitUntil("catalog") { !session.models.isEmpty }
        XCTAssertTrue(session.models[0].supportsEffort)
        XCTAssertEqual(session.models[0].supportedEffortLevels,
                       ["low", "medium", "high", "xhigh", "max"])
        XCTAssertFalse(session.models[1].supportsEffort)
        XCTAssertEqual(session.models[1].supportedEffortLevels, [])
    }

    func testSetEffortSendsSlashCommandAndSetsState() async throws {
        let (session, continuation, recorder) = makeSession()
        _ = continuation
        session.setEffort("medium")
        XCTAssertEqual(session.currentEffort, "medium")
        let entries = await waitForEntries(recorder, count: 1)
        XCTAssertEqual(entries, [.send("/effort medium")])
        // The local echo appears in the timeline like any user message.
        XCTAssertTrue(session.timeline.contains {
            if case .userMessage(_, "/effort medium") = $0 { return true }
            return false
        })
    }

    func testSyntheticSlashResultPreservesPendingGates() async throws {
        let (session, continuation, _) = makeSession()
        // A pending permission gate…
        try yield(continuation, #"""
        {"type":"control_request","request_id":"perm-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}}
        """#)
        await waitUntil("gate") { session.pendingGate != nil }
        // …must survive a synthetic slash-command result (num_turns == 0,
        // probe finding 12)…
        try yield(continuation, #"""
        {"type":"result","subtype":"success","is_error":false,"num_turns":0,"duration_ms":1,"result":"Set effort level to medium (this session only)","session_id":"s"}
        """#)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(session.pendingGate, "slash result must not clear gates")
        // …and still be cleared by a real turn's result (4a abort semantics).
        try yield(continuation, #"""
        {"type":"result","subtype":"error_during_execution","is_error":true,"num_turns":3,"duration_ms":100,"session_id":"s"}
        """#)
        await waitUntil("gate cleared") { session.pendingGate == nil }
    }

    func testLaunchEffortSeedsCurrentEffort() {
        let (connection, _, _) = makeFakeConnection()
        let session = ChatSession(
            connection: connection,
            workingDirectory: URL(fileURLWithPath: "/tmp/demo"),
            effort: "medium")
        XCTAssertEqual(session.currentEffort, "medium")
    }

    func testThinkingTokensTickerAccumulatesAndResets() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"thinking_tokens","estimated_tokens":44,"estimated_tokens_delta":17,"uuid":"tt1","session_id":"s"}
        """#)
        await waitUntil("ticker") { session.thinkingTokens == 44 }
        // estimated_tokens is cumulative — each event reassigns, not adds.
        try yield(continuation, #"""
        {"type":"system","subtype":"thinking_tokens","estimated_tokens":61,"estimated_tokens_delta":17,"uuid":"tt2","session_id":"s"}
        """#)
        await waitUntil("ticker update") { session.thinkingTokens == 61 }
        try yield(continuation, #"""
        {"type":"result","subtype":"success","is_error":false,"num_turns":1,"duration_ms":5,"session_id":"s"}
        """#)
        await waitUntil("reset") { session.thinkingTokens == nil }
    }

    func testTaskToolTrafficFeedsSessionTasks() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"assistant","message":{"role":"assistant","model":"m","content":[{"type":"tool_use","id":"toolu_1","name":"TaskCreate","input":{"subject":"Alpha task","description":"d","activeForm":"Alpha running"}}]},"session_id":"s","uuid":"a1"}
        """#)
        try yield(continuation, #"""
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_1","type":"tool_result","content":"Task #1 created successfully: Alpha task"}]},"session_id":"s","uuid":"u1","tool_use_result":{"task":{"id":"1","subject":"Alpha task"}}}
        """#)
        await waitUntil("task") { !session.sessionTasks.isEmpty }
        XCTAssertEqual(session.sessionTasks[0].taskID, "1")
        XCTAssertEqual(session.sessionTasks[0].subject, "Alpha task")
    }

    // MARK: - Control-op ack correlation + liveness (4b T6)

    func testRejectedSetModelRevertsAndNotices() async throws {
        let (session, continuation, recorder) = makeSession()
        // Session knows its model (catalog default path).
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init","response":{"commands":[],"models":[{"value":"default","resolvedModel":"claude-opus-4-8","displayName":"Default"}]}}}
        """#)
        await waitUntil("ready") { session.isReady }
        XCTAssertEqual(session.currentModel, "claude-opus-4-8")
        session.setModel("totally-bogus-model-9000")
        XCTAssertEqual(session.currentModel, "totally-bogus-model-9000",
                       "optimistic until the ack")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .setModel(_, let requestID) = entries.first else {
            return XCTFail("expected setModel, got \(entries)")
        }
        // Error ack with the recorded request id (badmodel fixture shape).
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"error","request_id":"\#(requestID)","error":"Model \"totally-bogus-model-9000\" is not a recognized model id."}}
        """#)
        await waitUntil("revert") { session.currentModel == "claude-opus-4-8" }
        XCTAssertTrue(session.timeline.contains {
            if case .notice(_, let text) = $0 { return text.contains("not a recognized") }
            return false
        }, "the rejection reason surfaces as a notice")
    }

    func testRejectedSetPermissionModeReverts() async throws {
        let (session, continuation, recorder) = makeSession()
        session.setPermissionMode("plan")
        XCTAssertEqual(session.permissionMode, "plan")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .setPermissionMode(_, let requestID) = entries.first else {
            return XCTFail("expected setPermissionMode, got \(entries)")
        }
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"error","request_id":"\#(requestID)","error":"nope"}}
        """#)
        await waitUntil("revert") { session.permissionMode == "default" }
        XCTAssertTrue(session.timeline.contains {
            if case .notice(_, let text) = $0 { return text.contains("nope") }
            return false
        }, "the rejection reason surfaces as a notice")
    }

    func testSuccessAckKeepsOptimisticValue() async throws {
        let (session, continuation, recorder) = makeSession()
        session.setModel("haiku")
        let entries = await waitForEntries(recorder, count: 1)
        guard case .setModel(_, let requestID) = entries.first else {
            return XCTFail("expected setModel, got \(entries)")
        }
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"\#(requestID)","response":{}}}
        """#)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(session.currentModel, "haiku")
    }

    func testLastEventAtTracksWireActivity() async throws {
        let (session, continuation, _) = makeSession()
        XCTAssertNil(session.lastEventAt)
        try yield(continuation, #"""
        {"type":"system","subtype":"status","status":"requesting","uuid":"s1","session_id":"s"}
        """#)
        await waitUntil("stamp") { session.lastEventAt != nil }
    }

    func testSendResetsLivenessBaseline() async throws {
        let (session, continuation, _) = makeSession()
        try yield(continuation, #"""
        {"type":"system","subtype":"status","status":"requesting","uuid":"s1","session_id":"s"}
        """#)
        await waitUntil("stamp") { session.lastEventAt != nil }
        let captured = try XCTUnwrap(session.lastEventAt)
        try await Task.sleep(for: .milliseconds(30))
        session.send("hi")
        let after = try XCTUnwrap(session.lastEventAt)
        XCTAssertGreaterThan(after, captured,
                             "send must reset the quiet-clock baseline")
    }

    func testStaleErrorAckDoesNotClobberNewerPick() async throws {
        let (session, continuation, recorder) = makeSession()
        session.setModel("model-a")
        session.setModel("model-b")
        let entries = await waitForEntries(recorder, count: 2)
        var reqA: String?
        var reqB: String?
        for entry in entries {
            if case .setModel("model-a", let id) = entry { reqA = id }
            if case .setModel("model-b", let id) = entry { reqB = id }
        }
        let staleID = try XCTUnwrap(reqA)
        let newerID = try XCTUnwrap(reqB)
        // The newer pick succeeds…
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"success","request_id":"\#(newerID)","response":{}}}
        """#)
        // …then the older pick's rejection arrives late. Its revert must not
        // clobber the newer value (last write wins).
        try yield(continuation, #"""
        {"type":"control_response","response":{"subtype":"error","request_id":"\#(staleID)","error":"stale rejection"}}
        """#)
        await waitUntil("stale ack processed") {
            session.timeline.contains {
                if case .notice(let id, _) = $0 {
                    return id == "control-error-\(staleID)"
                }
                return false
            }
        }
        XCTAssertEqual(session.currentModel, "model-b")
    }

    func testNoteworthyHookFiresForGateTurnAndTermination() async throws {
        let (session, continuation, _) = makeSession()
        var seen: [ChatSession.NoteworthyEvent] = []
        session.onNoteworthy = { seen.append($0) }
        try yield(continuation, #"""
        {"type":"control_request","request_id":"p1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"ls"}}}
        """#)
        try yield(continuation, #"""
        {"type":"system","subtype":"post_turn_summary","summarizes_uuid":"u","status_category":"review_ready","status_detail":"replied with READY-OK","needs_action":"","uuid":"pts","session_id":"s"}
        """#)
        try yield(continuation, #"""
        {"type":"result","subtype":"success","is_error":false,"num_turns":1,"duration_ms":45000,"session_id":"s"}
        """#)
        await waitUntil("hook") { seen.count >= 2 }
        guard case .gateArrived = seen[0] else { return XCTFail("expected gate, got \(seen)") }
        guard case .turnCompleted(let detail, let duration) = seen[1] else {
            return XCTFail("expected turn, got \(seen)")
        }
        XCTAssertEqual(detail, "replied with READY-OK")
        XCTAssertEqual(duration, 45000)
    }

    func testDraftIsSessionState() {
        let (connection, _, _) = makeFakeConnection()
        let a = ChatSession(connection: connection,
                            workingDirectory: URL(fileURLWithPath: "/tmp/a"))
        let b = ChatSession(connection: connection,
                            workingDirectory: URL(fileURLWithPath: "/tmp/b"))
        a.draft = "half-typed thought"
        XCTAssertEqual(a.draft, "half-typed thought")
        XCTAssertEqual(b.draft, "", "drafts never leak across sessions")
    }
}
