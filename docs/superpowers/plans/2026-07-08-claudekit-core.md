# ClaudeKit Core Implementation Plan (Fabled Plan 1 of 4)

> **STATUS: COMPLETE — merged to master 2026-07-08 (merge 3752358).** All 9 tasks executed by Opus subagents, per-task verification + Task 7 review loop + final gate review (READY). 25 tests (2 env-gated live). Deferred findings: docs/superpowers/FOLLOWUPS.md. Next: expand Plan 2 brief.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A UI-free Swift package (`ClaudeKit`) that spawns the Claude Code CLI, speaks its stream-json protocol (events, handshake, permission round-trip, control operations), proven by unit tests over recorded fixtures and an env-gated live integration test.

**Architecture:** Tolerant-decoding codec (`JSONValue` raw layer + typed `AgentEvent`) feeding an `AgentSession` actor that owns one CLI child process per session and exposes an `AsyncStream<AgentEvent>`. Outbound messages (user text, permission decisions, interrupt/set_model/set_permission_mode) are encoded as JSON lines on stdin. Unknown event types never throw — they surface as `.unknown` for generic rendering.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation `Process`/`Pipe`, XCTest. No third-party dependencies. macOS 15+.

**Roadmap context:** Plan 1 of 4. Plan 2 = SessionStore + history search. Plan 3 = SwiftUI app shell + conversation UI. Plan 4 = full surfaces (diffs, plan mode, embedded terminal, chat/cowork presets). Spec: `docs/superpowers/specs/2026-07-08-fabled-native-client-design.md`.

---

## Conventions for implementing agents

- Repo root: `~/Developer/Fabled`. All commands run from there.
- Build: `swift build`. Test: `swift test`. Both must be green before every commit. Never commit red.
- Swift 6 strict concurrency is ON. Everything public is `Sendable`. Process/pipe state lives inside the `AgentSession` actor only.
- Protocol ground truth: recorded captures in `fixtures/*.jsonl` (real CLI 2.1.202 output) and the spec's "Verified protocol facts" section. When in doubt, trust the fixtures over intuition.
- Do not use `--bare` (disables keychain auth). Do not remove `--verbose` (stream-json requires it).
- Tests that talk to the real CLI are gated: they run only when env `CLAUDEKIT_LIVE=1` is set. Everything else is offline.

## File structure

```
Package.swift
Sources/ClaudeKit/
  JSONValue.swift            # tolerant raw JSON representation
  AgentEvent.swift           # typed event enum + payload structs
  AgentEventDecoder.swift    # Data(line) -> AgentEvent, never-throw-on-unknown
  Outbound.swift             # outbound JSON-line encoders + PermissionDecision
  SessionConfiguration.swift # config + CLI argument builder
  AgentSession.swift         # actor: process lifecycle, handshake, event pump
Sources/fabled-probe/
  main.swift                 # tiny CLI harness for manual end-to-end runs
Tests/ClaudeKitTests/
  JSONValueTests.swift
  AgentEventDecoderTests.swift
  OutboundTests.swift
  SessionConfigurationTests.swift
  LiveSessionTests.swift     # env-gated, real CLI
  Fixtures.swift             # loads fixtures/ files + inline fixture lines
```

---

### Task 1: Package scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeKit/JSONValue.swift` (empty placeholder type)
- Create: `Tests/ClaudeKitTests/JSONValueTests.swift`
- Create: `.gitignore`

- [ ] **Step 1: Write Package.swift**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ClaudeKit", targets: ["ClaudeKit"]),
        .executable(name: "fabled-probe", targets: ["fabled-probe"]),
    ],
    targets: [
        .target(name: "ClaudeKit"),
        .executableTarget(name: "fabled-probe", dependencies: ["ClaudeKit"]),
        .testTarget(name: "ClaudeKitTests", dependencies: ["ClaudeKit"]),
    ]
)
```

- [ ] **Step 2: Write .gitignore**

```
.build/
.swiftpm/
xcuserdata/
DerivedData/
```

- [ ] **Step 3: Create minimal source + test so the package builds**

`Sources/ClaudeKit/JSONValue.swift`:
```swift
public enum JSONValue: Sendable, Equatable {
    case null
}
```

`Sources/fabled-probe/main.swift`:
```swift
print("fabled-probe placeholder")
```

`Tests/ClaudeKitTests/JSONValueTests.swift`:
```swift
import XCTest
@testable import ClaudeKit

final class JSONValueTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertEqual(JSONValue.null, JSONValue.null)
    }
}
```

- [ ] **Step 4: Verify build and tests pass**

Run: `swift test`
Expected: `Test Suite 'All tests' passed` (1 test).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ClaudeKit package scaffold"
```

---

### Task 2: JSONValue — tolerant raw JSON

**Files:**
- Modify: `Sources/ClaudeKit/JSONValue.swift` (replace placeholder)
- Modify: `Tests/ClaudeKitTests/JSONValueTests.swift` (replace placeholder)

- [ ] **Step 1: Write the failing tests**

Replace `Tests/ClaudeKitTests/JSONValueTests.swift` with:

```swift
import XCTest
@testable import ClaudeKit

final class JSONValueTests: XCTestCase {
    func testDecodesArbitraryObject() throws {
        let data = Data(#"{"a":1,"b":"x","c":[true,null],"d":{"e":2.5}}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(v["a"], .number(1))
        XCTAssertEqual(v["b"]?.stringValue, "x")
        XCTAssertEqual(v["c"], .array([.bool(true), .null]))
        XCTAssertEqual(v["d"]?["e"], .number(2.5))
    }

    func testRoundTripsThroughEncoder() throws {
        let data = Data(#"{"nested":{"list":[1,"two",false,null]}}"#.utf8)
        let v = try JSONDecoder().decode(JSONValue.self, from: data)
        let encoded = try JSONEncoder().encode(v)
        let v2 = try JSONDecoder().decode(JSONValue.self, from: encoded)
        XCTAssertEqual(v, v2)
    }

    func testConvenienceAccessors() throws {
        let v = try JSONDecoder().decode(
            JSONValue.self,
            from: Data(#"{"s":"hi","n":3,"b":true,"arr":[{"k":"v"}]}"#.utf8))
        XCTAssertEqual(v["s"]?.stringValue, "hi")
        XCTAssertEqual(v["n"]?.doubleValue, 3)
        XCTAssertEqual(v["b"]?.boolValue, true)
        XCTAssertEqual(v["arr"]?.arrayValue?.first?["k"]?.stringValue, "v")
        XCTAssertNil(v["missing"])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (missing cases/accessors) — that is the failure.

- [ ] **Step 3: Implement JSONValue**

Replace `Sources/ClaudeKit/JSONValue.swift` with:

```swift
public enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var doubleValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }
    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let b): try container.encode(b)
        case .number(let n): try container.encode(n)
        case .string(let s): try container.encode(s)
        case .array(let a): try container.encode(a)
        case .object(let o): try container.encode(o)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS (3 tests + probe still builds).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: JSONValue tolerant raw JSON representation"
```

---

### Task 3: Fixture loader + AgentEvent decoding (init, system, unknown)

**Files:**
- Create: `Sources/ClaudeKit/AgentEvent.swift`
- Create: `Sources/ClaudeKit/AgentEventDecoder.swift`
- Create: `Tests/ClaudeKitTests/Fixtures.swift`
- Create: `Tests/ClaudeKitTests/AgentEventDecoderTests.swift`

- [ ] **Step 1: Write the fixture loader**

`Tests/ClaudeKitTests/Fixtures.swift`:

```swift
import Foundation

enum Fixtures {
    /// Repo-root fixtures/ directory, resolved relative to this source file.
    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ClaudeKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("fixtures")
    }

    static func lines(_ name: String) throws -> [Data] {
        let url = fixturesDir.appendingPathComponent(name)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").map { Data($0.utf8) }
    }

    /// Real init event shape captured 2026-07-08 (abbreviated field set, same structure).
    static let initLine = Data(#"""
    {"type":"system","subtype":"init","cwd":"/tmp/x","session_id":"9753c268-9f22-44da-b0c2-2aed628498a9","tools":["Bash","Edit","Read"],"mcp_servers":[],"model":"claude-haiku-4-5-20251001","permissionMode":"default","slash_commands":["init","review"],"apiKeySource":"none","claude_code_version":"2.1.202","output_style":"default","agents":["claude","Plan"],"skills":["verify"],"uuid":"9e04c0f6-d0e8-4033-b79e-e1b8ed3668ac"}
    """#.utf8)

    static let thinkingLine = Data(#"""
    {"type":"system","subtype":"thinking_tokens","tokens":128,"uuid":"aa04c0f6-d0e8-4033-b79e-e1b8ed3668ac"}
    """#.utf8)

    static let futureEventLine = Data(#"""
    {"type":"hologram_projection","payload":{"x":1}}
    """#.utf8)
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/ClaudeKitTests/AgentEventDecoderTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class AgentEventDecoderTests: XCTestCase {
    func testDecodesSystemInit() throws {
        let event = try AgentEventDecoder.decode(Fixtures.initLine)
        guard case .systemInit(let info) = event else {
            return XCTFail("expected systemInit, got \(event)")
        }
        XCTAssertEqual(info.sessionID, "9753c268-9f22-44da-b0c2-2aed628498a9")
        XCTAssertEqual(info.model, "claude-haiku-4-5-20251001")
        XCTAssertEqual(info.tools, ["Bash", "Edit", "Read"])
        XCTAssertEqual(info.permissionMode, "default")
        XCTAssertEqual(info.slashCommands, ["init", "review"])
        XCTAssertEqual(info.cliVersion, "2.1.202")
    }

    func testDecodesOtherSystemSubtypesGenerically() throws {
        let event = try AgentEventDecoder.decode(Fixtures.thinkingLine)
        guard case .system(let subtype, let raw) = event else {
            return XCTFail("expected system, got \(event)")
        }
        XCTAssertEqual(subtype, "thinking_tokens")
        XCTAssertEqual(raw["tokens"], .number(128))
    }

    func testUnknownTypeDoesNotThrow() throws {
        let event = try AgentEventDecoder.decode(Fixtures.futureEventLine)
        guard case .unknown(let type, let raw) = event else {
            return XCTFail("expected unknown, got \(event)")
        }
        XCTAssertEqual(type, "hologram_projection")
        XCTAssertEqual(raw["payload"]?["x"], .number(1))
    }

    func testMalformedLineThrows() {
        XCTAssertThrowsError(try AgentEventDecoder.decode(Data("not json".utf8)))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (AgentEvent/AgentEventDecoder undefined).

- [ ] **Step 4: Implement AgentEvent and the decoder skeleton**

`Sources/ClaudeKit/AgentEvent.swift`:

```swift
public struct SystemInit: Sendable, Equatable {
    public let sessionID: String
    public let model: String
    public let cwd: String
    public let tools: [String]
    public let permissionMode: String
    public let slashCommands: [String]
    public let agents: [String]
    public let skills: [String]
    public let cliVersion: String
    public let raw: JSONValue
}

public enum AgentEvent: Sendable {
    case systemInit(SystemInit)
    case system(subtype: String, raw: JSONValue)
    case unknown(type: String, raw: JSONValue)
}
```

`Sources/ClaudeKit/AgentEventDecoder.swift`:

```swift
import Foundation

public enum AgentEventDecoder {
    public static func decode(_ line: Data) throws -> AgentEvent {
        let raw = try JSONDecoder().decode(JSONValue.self, from: line)
        let type = raw["type"]?.stringValue ?? ""
        switch type {
        case "system":
            let subtype = raw["subtype"]?.stringValue ?? ""
            if subtype == "init" { return .systemInit(Self.systemInit(from: raw)) }
            return .system(subtype: subtype, raw: raw)
        default:
            return .unknown(type: type, raw: raw)
        }
    }

    static func strings(_ value: JSONValue?) -> [String] {
        value?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    static func systemInit(from raw: JSONValue) -> SystemInit {
        SystemInit(
            sessionID: raw["session_id"]?.stringValue ?? "",
            model: raw["model"]?.stringValue ?? "",
            cwd: raw["cwd"]?.stringValue ?? "",
            tools: strings(raw["tools"]),
            permissionMode: raw["permissionMode"]?.stringValue ?? "",
            slashCommands: strings(raw["slash_commands"]),
            agents: strings(raw["agents"]),
            skills: strings(raw["skills"]),
            cliVersion: raw["claude_code_version"]?.stringValue ?? "",
            raw: raw)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: AgentEvent decoding for init/system/unknown events"
```

---

### Task 4: Assistant messages, tool results, turn results

**Files:**
- Modify: `Sources/ClaudeKit/AgentEvent.swift`
- Modify: `Sources/ClaudeKit/AgentEventDecoder.swift`
- Modify: `Tests/ClaudeKitTests/AgentEventDecoderTests.swift`

- [ ] **Step 1: Add the failing tests**

Append to `AgentEventDecoderTests.swift`:

```swift
    func testDecodesAssistantTextAndToolUse() throws {
        let line = Data(#"""
        {"type":"assistant","message":{"role":"assistant","model":"claude-haiku-4-5-20251001","content":[{"type":"text","text":"Done."},{"type":"tool_use","id":"toolu_01","name":"Bash","input":{"command":"echo hi"}}]},"parent_tool_use_id":null,"session_id":"s1","uuid":"u1"}
        """#.utf8)
        guard case .assistant(let msg) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected assistant")
        }
        XCTAssertEqual(msg.content.count, 2)
        XCTAssertEqual(msg.content[0], .text("Done."))
        XCTAssertEqual(msg.content[1],
            .toolUse(id: "toolu_01", name: "Bash",
                     input: .object(["command": .string("echo hi")])))
    }

    func testDecodesToolResultUserEvent() throws {
        let line = Data(#"""
        {"type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"hello-from-test","is_error":false}]},"session_id":"s1","uuid":"u2"}
        """#.utf8)
        guard case .toolResult(let results) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected toolResult")
        }
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].toolUseID, "toolu_01")
        XCTAssertEqual(results[0].content.stringValue, "hello-from-test")
        XCTAssertFalse(results[0].isError)
    }

    func testDecodesResultEvent() throws {
        let line = Data(#"""
        {"type":"result","subtype":"success","is_error":false,"duration_ms":15,"num_turns":1,"result":"ok","session_id":"s1","total_cost_usd":0.0021,"usage":{"input_tokens":10,"output_tokens":5},"permission_denials":[{"tool_name":"Bash"}],"uuid":"u3"}
        """#.utf8)
        guard case .result(let r) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected result")
        }
        XCTAssertEqual(r.subtype, "success")
        XCTAssertFalse(r.isError)
        XCTAssertEqual(r.totalCostUSD, 0.0021)
        XCTAssertEqual(r.permissionDenials.count, 1)
    }

    func testDecodesEntireRecordedCaptureWithoutUnknowns() throws {
        for name in ["2026-07-08-sandboxed-bash-no-handshake.jsonl",
                     "2026-07-08-auto-deny-no-permission-tool.jsonl"] {
            for line in try Fixtures.lines(name) {
                let event = try AgentEventDecoder.decode(line)
                if case .unknown(let type, _) = event {
                    XCTFail("unknown event type \(type) in \(name)")
                }
            }
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors (missing cases).

- [ ] **Step 3: Implement the new event types**

Append to `Sources/ClaudeKit/AgentEvent.swift`:

```swift
public enum ContentBlock: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolUse(id: String, name: String, input: JSONValue)
    case unknown(type: String, raw: JSONValue)
}

public struct AssistantMessage: Sendable, Equatable {
    public let content: [ContentBlock]
    public let model: String?
    public let sessionID: String?
    public let parentToolUseID: String?
    public let raw: JSONValue
}

public struct ToolResult: Sendable, Equatable {
    public let toolUseID: String
    public let content: JSONValue
    public let isError: Bool
}

public struct TurnResult: Sendable, Equatable {
    public let subtype: String
    public let isError: Bool
    public let durationMS: Double?
    public let totalCostUSD: Double?
    public let usage: JSONValue?
    public let permissionDenials: [JSONValue]
    public let raw: JSONValue
}
```

And extend the enum:

```swift
// add cases to AgentEvent:
    case assistant(AssistantMessage)
    case toolResult([ToolResult])
    case result(TurnResult)
```

- [ ] **Step 4: Implement decoding**

In `AgentEventDecoder.decode`, add before `default:`:

```swift
        case "assistant":
            let message = raw["message"]
            let blocks = (message?["content"]?.arrayValue ?? []).map(Self.contentBlock)
            return .assistant(AssistantMessage(
                content: blocks,
                model: message?["model"]?.stringValue,
                sessionID: raw["session_id"]?.stringValue,
                parentToolUseID: raw["parent_tool_use_id"]?.stringValue,
                raw: raw))
        case "user":
            let blocks = raw["message"]?["content"]?.arrayValue ?? []
            let results = blocks.compactMap { block -> ToolResult? in
                guard block["type"]?.stringValue == "tool_result",
                      let id = block["tool_use_id"]?.stringValue else { return nil }
                return ToolResult(
                    toolUseID: id,
                    content: block["content"] ?? .null,
                    isError: block["is_error"]?.boolValue ?? false)
            }
            return .toolResult(results)
        case "result":
            return .result(TurnResult(
                subtype: raw["subtype"]?.stringValue ?? "",
                isError: raw["is_error"]?.boolValue ?? false,
                durationMS: raw["duration_ms"]?.doubleValue,
                totalCostUSD: raw["total_cost_usd"]?.doubleValue,
                usage: raw["usage"],
                permissionDenials: raw["permission_denials"]?.arrayValue ?? [],
                raw: raw))
        case "rate_limit_event":
            return .system(subtype: "rate_limit_event", raw: raw)
```

Add the helper:

```swift
    static func contentBlock(_ block: JSONValue) -> ContentBlock {
        switch block["type"]?.stringValue {
        case "text":
            return .text(block["text"]?.stringValue ?? "")
        case "thinking":
            return .thinking(block["thinking"]?.stringValue ?? "")
        case "tool_use":
            return .toolUse(
                id: block["id"]?.stringValue ?? "",
                name: block["name"]?.stringValue ?? "",
                input: block["input"] ?? .null)
        default:
            return .unknown(type: block["type"]?.stringValue ?? "", raw: block)
        }
    }
```

Note: the recorded captures also contain `queue-operation` lines only in *session transcripts on disk*, not in live stream output — if `testDecodesEntireRecordedCaptureWithoutUnknowns` fails on an event type that genuinely appears in the capture files, add it as a `.system(subtype:raw:)` mapping rather than weakening the test.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS, including whole-capture decoding.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: decode assistant, tool result, and turn result events"
```

---

### Task 5: Control protocol — inbound requests and outbound encoding

**Files:**
- Modify: `Sources/ClaudeKit/AgentEvent.swift`
- Modify: `Sources/ClaudeKit/AgentEventDecoder.swift`
- Create: `Sources/ClaudeKit/Outbound.swift`
- Create: `Tests/ClaudeKitTests/OutboundTests.swift`
- Modify: `Tests/ClaudeKitTests/AgentEventDecoderTests.swift`

- [ ] **Step 1: Add failing decoder tests for control events**

Append to `AgentEventDecoderTests.swift` (this is the real `can_use_tool` shape captured 2026-07-08):

```swift
    func testDecodesCanUseToolControlRequest() throws {
        let line = Data(#"""
        {"type":"control_request","request_id":"4565ced1-e35b-4fbc-bb6a-c87dc03b4747","request":{"subtype":"can_use_tool","tool_name":"Bash","display_name":"Bash","input":{"command":"git init","description":"Initialize a new git repository"},"description":"Initialize a new git repository","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"git init *"}],"behavior":"allow","destination":"localSettings"}],"decision_reason":"This command requires approval"}}
        """#.utf8)
        guard case .controlRequest(let req) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected controlRequest")
        }
        XCTAssertEqual(req.requestID, "4565ced1-e35b-4fbc-bb6a-c87dc03b4747")
        XCTAssertEqual(req.subtype, "can_use_tool")
        let perm = try XCTUnwrap(PermissionRequest(req))
        XCTAssertEqual(perm.toolName, "Bash")
        XCTAssertEqual(perm.input["command"]?.stringValue, "git init")
        XCTAssertEqual(perm.suggestions.count, 1)
    }

    func testDecodesControlResponse() throws {
        let line = Data(#"""
        {"type":"control_response","response":{"subtype":"success","request_id":"init-1","response":{"commands":[{"name":"review","description":"Review a PR","argumentHint":""}]}}}
        """#.utf8)
        guard case .controlResponse(let resp) = try AgentEventDecoder.decode(line) else {
            return XCTFail("expected controlResponse")
        }
        XCTAssertEqual(resp.requestID, "init-1")
        XCTAssertEqual(resp.payload?["commands"]?.arrayValue?.count, 1)
    }
```

- [ ] **Step 2: Add failing outbound-encoding tests**

`Tests/ClaudeKitTests/OutboundTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class OutboundTests: XCTestCase {
    private func json(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    func testUserMessage() throws {
        let v = try json(Outbound.userMessage("hello"))
        XCTAssertEqual(v["type"]?.stringValue, "user")
        XCTAssertEqual(v["message"]?["role"]?.stringValue, "user")
        XCTAssertEqual(v["message"]?["content"]?.stringValue, "hello")
    }

    func testInitialize() throws {
        let v = try json(Outbound.initialize(requestID: "init-1"))
        XCTAssertEqual(v["type"]?.stringValue, "control_request")
        XCTAssertEqual(v["request_id"]?.stringValue, "init-1")
        XCTAssertEqual(v["request"]?["subtype"]?.stringValue, "initialize")
    }

    func testAllowPermissionResponse() throws {
        let input: JSONValue = .object(["command": .string("git init")])
        let v = try json(Outbound.permissionResponse(
            requestID: "r1", decision: .allow(updatedInput: input)))
        XCTAssertEqual(v["type"]?.stringValue, "control_response")
        XCTAssertEqual(v["response"]?["subtype"]?.stringValue, "success")
        XCTAssertEqual(v["response"]?["request_id"]?.stringValue, "r1")
        XCTAssertEqual(v["response"]?["response"]?["behavior"]?.stringValue, "allow")
        XCTAssertEqual(v["response"]?["response"]?["updatedInput"]?["command"]?.stringValue,
                       "git init")
    }

    func testDenyPermissionResponse() throws {
        let v = try json(Outbound.permissionResponse(
            requestID: "r2", decision: .deny(message: "not now")))
        XCTAssertEqual(v["response"]?["response"]?["behavior"]?.stringValue, "deny")
        XCTAssertEqual(v["response"]?["response"]?["message"]?.stringValue, "not now")
    }

    func testControlRequestOp() throws {
        let v = try json(Outbound.controlRequest(
            requestID: "r3", subtype: "set_model",
            extra: ["model": .string("claude-fable-5")]))
        XCTAssertEqual(v["request"]?["subtype"]?.stringValue, "set_model")
        XCTAssertEqual(v["request"]?["model"]?.stringValue, "claude-fable-5")
    }

    func testOutputEndsWithNewline() {
        XCTAssertEqual(Outbound.userMessage("x").last, UInt8(ascii: "\n"))
        XCTAssertEqual(Outbound.initialize(requestID: "i").last, UInt8(ascii: "\n"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test`
Expected: compile errors.

- [ ] **Step 4: Implement control types and outbound encoders**

Append to `Sources/ClaudeKit/AgentEvent.swift`:

```swift
public struct ControlRequest: Sendable, Equatable {
    public let requestID: String
    public let subtype: String
    public let payload: JSONValue
}

public struct ControlResponseEnvelope: Sendable, Equatable {
    public let requestID: String
    public let subtype: String
    public let payload: JSONValue?
}

public struct PermissionRequest: Sendable, Equatable {
    public let requestID: String
    public let toolName: String
    public let displayName: String?
    public let input: JSONValue
    public let description: String?
    public let decisionReason: String?
    public let suggestions: [JSONValue]

    public init?(_ request: ControlRequest) {
        guard request.subtype == "can_use_tool",
              let toolName = request.payload["tool_name"]?.stringValue else { return nil }
        self.requestID = request.requestID
        self.toolName = toolName
        self.displayName = request.payload["display_name"]?.stringValue
        self.input = request.payload["input"] ?? .null
        self.description = request.payload["description"]?.stringValue
        self.decisionReason = request.payload["decision_reason"]?.stringValue
        self.suggestions = request.payload["permission_suggestions"]?.arrayValue ?? []
    }
}
```

Add cases to `AgentEvent`:

```swift
    case controlRequest(ControlRequest)
    case controlResponse(ControlResponseEnvelope)
```

In `AgentEventDecoder.decode`, add before `default:`:

```swift
        case "control_request":
            return .controlRequest(ControlRequest(
                requestID: raw["request_id"]?.stringValue ?? "",
                subtype: raw["request"]?["subtype"]?.stringValue ?? "",
                payload: raw["request"] ?? .null))
        case "control_response":
            let response = raw["response"]
            return .controlResponse(ControlResponseEnvelope(
                requestID: response?["request_id"]?.stringValue ?? "",
                subtype: response?["subtype"]?.stringValue ?? "",
                payload: response?["response"]))
```

`Sources/ClaudeKit/Outbound.swift`:

```swift
import Foundation

public enum PermissionDecision: Sendable {
    case allow(updatedInput: JSONValue?)
    case deny(message: String?)
}

public enum Outbound {
    static func encodeLine(_ value: JSONValue) -> Data {
        var data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func userMessage(_ text: String) -> Data {
        encodeLine(.object([
            "type": .string("user"),
            "message": .object([
                "role": .string("user"),
                "content": .string(text),
            ]),
        ]))
    }

    public static func initialize(requestID: String) -> Data {
        controlRequest(requestID: requestID, subtype: "initialize",
                       extra: ["hooks": .object([:])])
    }

    public static func controlRequest(
        requestID: String, subtype: String, extra: [String: JSONValue] = [:]
    ) -> Data {
        var request: [String: JSONValue] = ["subtype": .string(subtype)]
        for (k, v) in extra { request[k] = v }
        return encodeLine(.object([
            "type": .string("control_request"),
            "request_id": .string(requestID),
            "request": .object(request),
        ]))
    }

    public static func permissionResponse(
        requestID: String, decision: PermissionDecision
    ) -> Data {
        var inner: [String: JSONValue]
        switch decision {
        case .allow(let updatedInput):
            inner = ["behavior": .string("allow")]
            if let updatedInput { inner["updatedInput"] = updatedInput }
        case .deny(let message):
            inner = ["behavior": .string("deny")]
            if let message { inner["message"] = .string(message) }
        }
        return encodeLine(.object([
            "type": .string("control_response"),
            "response": .object([
                "subtype": .string("success"),
                "request_id": .string(requestID),
                "response": .object(inner),
            ]),
        ]))
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: control protocol types and outbound encoders"
```

---

### Task 6: SessionConfiguration and argument builder

**Files:**
- Create: `Sources/ClaudeKit/SessionConfiguration.swift`
- Create: `Tests/ClaudeKitTests/SessionConfigurationTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import ClaudeKit

final class SessionConfigurationTests: XCTestCase {
    func testBaseArguments() {
        let config = SessionConfiguration(
            workingDirectory: URL(fileURLWithPath: "/tmp/x"))
        XCTAssertEqual(config.arguments(), [
            "-p", "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--permission-prompt-tool", "stdio",
        ])
    }

    func testAllOptions() {
        var config = SessionConfiguration(
            workingDirectory: URL(fileURLWithPath: "/tmp/x"))
        config.model = "claude-fable-5"
        config.resumeSessionID = "abc-123"
        config.forkSession = true
        config.permissionMode = "acceptEdits"
        let args = config.arguments()
        XCTAssertTrue(args.contains("--model"))
        XCTAssertEqual(args[args.firstIndex(of: "--model")! + 1], "claude-fable-5")
        XCTAssertEqual(args[args.firstIndex(of: "--resume")! + 1], "abc-123")
        XCTAssertTrue(args.contains("--fork-session"))
        XCTAssertEqual(args[args.firstIndex(of: "--permission-mode")! + 1], "acceptEdits")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test` — compile error expected.

- [ ] **Step 3: Implement**

`Sources/ClaudeKit/SessionConfiguration.swift`:

```swift
import Foundation

public struct SessionConfiguration: Sendable {
    /// nil = resolve `claude` via /usr/bin/env from PATH.
    public var executable: URL?
    public var workingDirectory: URL
    public var model: String?
    public var resumeSessionID: String?
    public var forkSession: Bool = false
    public var permissionMode: String?
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
        if let model { args += ["--model", model] }
        if let resumeSessionID { args += ["--resume", resumeSessionID] }
        if forkSession { args.append("--fork-session") }
        if let permissionMode { args += ["--permission-mode", permissionMode] }
        args += extraArguments
        return args
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test` — PASS.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: SessionConfiguration and CLI argument builder"
```

---

### Task 7: AgentSession actor — process lifecycle and event pump

**Files:**
- Create: `Sources/ClaudeKit/AgentSession.swift`
- Create: `Tests/ClaudeKitTests/AgentSessionTests.swift`

The unit tests use a **fake CLI**: a tiny shell script that replays a fixture and echoes stdin, so process plumbing is tested offline and deterministically.

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeKitTests/AgentSessionTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

final class AgentSessionTests: XCTestCase {
    /// Writes a fake `claude` that: prints an init line, echoes every stdin
    /// line to a capture file, then prints a result line and exits.
    private func makeFakeCLI() throws -> (executable: URL, capture: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let capture = dir.appendingPathComponent("stdin-capture.jsonl")
        let script = dir.appendingPathComponent("claude")
        let initLine = String(data: Fixtures.initLine, encoding: .utf8)!
        let body = """
        #!/bin/bash
        echo '\(initLine)'
        while IFS= read -r line; do
          echo "$line" >> '\(capture.path)'
          if [[ "$line" == *'"type":"user"'* ]]; then
            echo '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"pong"}]},"session_id":"s1"}'
            echo '{"type":"result","subtype":"success","is_error":false,"session_id":"s1"}'
            exit 0
          fi
        done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script, capture)
    }

    func testSessionLifecycle() async throws {
        let (fake, capture) = try makeFakeCLI()
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = fake

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("ping")

        var sawInit = false
        var texts: [String] = []
        var terminated = false
        for await event in await session.events {
            switch event {
            case .systemInit: sawInit = true
            case .assistant(let msg):
                for case .text(let t) in msg.content { texts.append(t) }
            case .terminated: terminated = true
            default: break
            }
        }
        XCTAssertTrue(sawInit)
        XCTAssertEqual(texts, ["pong"])
        XCTAssertTrue(terminated)

        let written = try String(contentsOf: capture, encoding: .utf8)
        XCTAssertTrue(written.contains(#""subtype":"initialize""#),
                      "handshake must be sent first")
        XCTAssertTrue(written.contains(#""content":"ping""#))
        let lines = written.split(separator: "\n")
        XCTAssertTrue(lines[0].contains("initialize"),
                      "initialize must precede user messages")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test` — compile error (AgentSession undefined).

- [ ] **Step 3: Implement AgentSession**

`Sources/ClaudeKit/AgentSession.swift`:

```swift
import Foundation

public actor AgentSession {
    public enum SessionError: Error {
        case alreadyStarted
        case launchFailed(String)
    }

    private let configuration: SessionConfiguration
    private var process: Process?
    private var stdinPipe: Pipe?
    private var continuation: AsyncStream<AgentEvent>.Continuation?
    private var readTask: Task<Void, Never>?

    /// Single-consumer stream of everything the CLI emits, plus `.terminated`.
    public private(set) var events: AsyncStream<AgentEvent> = AsyncStream { $0.finish() }

    public init(configuration: SessionConfiguration) {
        self.configuration = configuration
    }

    public func start() async throws {
        guard process == nil else { throw SessionError.alreadyStarted }

        let (stream, continuation) = AsyncStream.makeStream(of: AgentEvent.self)
        self.events = stream
        self.continuation = continuation

        let process = Process()
        if let executable = configuration.executable {
            process.executableURL = executable
            process.arguments = configuration.arguments()
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["claude"] + configuration.arguments()
        }
        process.currentDirectoryURL = configuration.workingDirectory

        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        process.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { await self?.handleTermination(exitCode: code) }
        }

        do {
            try process.run()
        } catch {
            throw SessionError.launchFailed(String(describing: error))
        }
        self.process = process
        self.stdinPipe = stdin

        readTask = Task { [weak self] in
            do {
                for try await line in stdout.fileHandleForReading.bytes.lines {
                    guard let self else { return }
                    if let event = try? AgentEventDecoder.decode(Data(line.utf8)) {
                        await self.emit(event)
                    }
                }
            } catch {
                // Pipe closed — termination handler emits .terminated.
            }
        }

        write(Outbound.initialize(requestID: "init-\(UUID().uuidString)"))
    }

    public func send(_ text: String) {
        write(Outbound.userMessage(text))
    }

    public func respond(to request: PermissionRequest, decision: PermissionDecision) {
        write(Outbound.permissionResponse(requestID: request.requestID,
                                          decision: decision))
    }

    public func interrupt() {
        sendControl(subtype: "interrupt")
    }

    public func setModel(_ model: String) {
        sendControl(subtype: "set_model", extra: ["model": .string(model)])
    }

    public func setPermissionMode(_ mode: String) {
        sendControl(subtype: "set_permission_mode", extra: ["mode": .string(mode)])
    }

    public func terminate() {
        process?.terminate()
    }

    private func sendControl(subtype: String, extra: [String: JSONValue] = [:]) {
        write(Outbound.controlRequest(
            requestID: UUID().uuidString, subtype: subtype, extra: extra))
    }

    private func write(_ data: Data) {
        try? stdinPipe?.fileHandleForWriting.write(contentsOf: data)
    }

    private func emit(_ event: AgentEvent) {
        continuation?.yield(event)
    }

    private func handleTermination(exitCode: Int32) {
        continuation?.yield(.terminated(exitCode: exitCode))
        continuation?.finish()
        continuation = nil
        readTask?.cancel()
    }
}
```

Add the case to `AgentEvent` in `AgentEvent.swift`:

```swift
    case terminated(exitCode: Int32)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: PASS. If the lifecycle test hangs, the fake CLI never saw the user line — check that `Outbound` output is newline-terminated (Task 5 test covers this).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: AgentSession actor with process lifecycle and event pump"
```

---

### Task 8: Permission round-trip against the fake CLI

**Files:**
- Modify: `Tests/ClaudeKitTests/AgentSessionTests.swift`

This task proves the full loop offline: fake CLI emits a real captured `can_use_tool` line; the test answers via `respond(to:decision:)`; the fake CLI verifies the response shape before emitting success.

- [ ] **Step 1: Write the failing test**

Append to `AgentSessionTests.swift`:

```swift
    private func makePermissionFakeCLI() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("claude")
        let body = """
        #!/bin/bash
        echo '{"type":"control_request","request_id":"perm-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"git init"},"permission_suggestions":[]}}'
        while IFS= read -r line; do
          if [[ "$line" == *'"request_id":"perm-1"'* && "$line" == *'"behavior":"allow"'* ]]; then
            echo '{"type":"result","subtype":"success","is_error":false,"session_id":"s1"}'
            exit 0
          fi
        done
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    func testPermissionRoundTrip() async throws {
        var config = SessionConfiguration(
            workingDirectory: FileManager.default.temporaryDirectory)
        config.executable = try makePermissionFakeCLI()

        let session = AgentSession(configuration: config)
        try await session.start()

        var gotResult = false
        for await event in await session.events {
            switch event {
            case .controlRequest(let req):
                if let perm = PermissionRequest(req) {
                    XCTAssertEqual(perm.toolName, "Bash")
                    await session.respond(
                        to: perm, decision: .allow(updatedInput: perm.input))
                }
            case .result: gotResult = true
            default: break
            }
        }
        XCTAssertTrue(gotResult,
            "fake CLI only emits result if it received a well-formed allow response")
    }
```

- [ ] **Step 2: Run test to verify it fails or passes for the right reason**

Run: `swift test --filter testPermissionRoundTrip`
Expected: PASS if Tasks 5+7 are correct — the point of this test is guarding the *integration* of codec and session. If it hangs, the response encoding doesn't match what the fake CLI greps for; fix `Outbound.permissionResponse`, not the test.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "test: offline permission round-trip through AgentSession"
```

---

### Task 9: Live integration test + probe executable

**Files:**
- Create: `Tests/ClaudeKitTests/LiveSessionTests.swift`
- Modify: `Sources/fabled-probe/main.swift`

- [ ] **Step 1: Write the env-gated live test**

`Tests/ClaudeKitTests/LiveSessionTests.swift`:

```swift
import XCTest
@testable import ClaudeKit

/// Real-CLI tests. Run with: CLAUDEKIT_LIVE=1 swift test --filter LiveSessionTests
/// Uses haiku for cost; requires the user to be logged in to claude.
final class LiveSessionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? XCTSkipUnless(
            ProcessInfo.processInfo.environment["CLAUDEKIT_LIVE"] == "1",
            "set CLAUDEKIT_LIVE=1 to run live CLI tests")
    }

    private func scratchDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testLivePingPong() async throws {
        var config = SessionConfiguration(workingDirectory: try scratchDir())
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Reply with exactly the word: pong")

        var sawInit = false
        var text = ""
        for await event in await session.events {
            switch event {
            case .systemInit(let info):
                sawInit = true
                XCTAssertFalse(info.sessionID.isEmpty)
            case .assistant(let msg):
                for case .text(let t) in msg.content { text += t }
            case .result:
                await session.terminate()
            default: break
            }
        }
        XCTAssertTrue(sawInit)
        XCTAssertTrue(text.lowercased().contains("pong"), "got: \(text)")
    }

    func testLivePermissionRoundTrip() async throws {
        var config = SessionConfiguration(workingDirectory: try scratchDir())
        config.model = "haiku"
        config.extraArguments = ["--setting-sources", ""]

        let session = AgentSession(configuration: config)
        try await session.start()
        await session.send("Run exactly this bash command: git init")

        var approved = false
        var toolSucceeded = false
        for await event in await session.events {
            switch event {
            case .controlRequest(let req):
                if let perm = PermissionRequest(req) {
                    approved = true
                    await session.respond(
                        to: perm, decision: .allow(updatedInput: perm.input))
                }
            case .toolResult(let results):
                if results.contains(where: { !$0.isError }) { toolSucceeded = true }
            case .result(let r):
                XCTAssertTrue(r.permissionDenials.isEmpty)
                await session.terminate()
            default: break
            }
        }
        XCTAssertTrue(approved, "expected a can_use_tool request for git init")
        XCTAssertTrue(toolSucceeded)
    }
}
```

- [ ] **Step 2: Run offline suite to confirm live tests skip cleanly**

Run: `swift test`
Expected: PASS with `LiveSessionTests` skipped.

- [ ] **Step 3: Run the live tests**

Run: `CLAUDEKIT_LIVE=1 swift test --filter LiveSessionTests`
Expected: 2 PASS (needs logged-in claude; costs ~1 cent on haiku). If `testLivePermissionRoundTrip` fails because no permission request arrived, check that `git init` wasn't auto-allowed by user settings — the `--setting-sources ""` argument should prevent that.

- [ ] **Step 4: Implement the probe executable**

Replace `Sources/fabled-probe/main.swift`:

```swift
import Foundation
import ClaudeKit

// Usage: fabled-probe [--model X] [--cwd DIR] "prompt"
// Streams events to stdout; auto-allows all permission requests. Manual harness only.
var args = Array(CommandLine.arguments.dropFirst())
var config = SessionConfiguration(
    workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
config.model = "haiku"

while args.count >= 2, args[0].hasPrefix("--") {
    switch args[0] {
    case "--model": config.model = args[1]
    case "--cwd": config.workingDirectory = URL(fileURLWithPath: args[1])
    default: FileHandle.standardError.write(Data("unknown flag \(args[0])\n".utf8))
    }
    args.removeFirst(2)
}
guard let prompt = args.first else {
    print("usage: fabled-probe [--model X] [--cwd DIR] \"prompt\"")
    exit(1)
}

let session = AgentSession(configuration: config)
try await session.start()
await session.send(prompt)

for await event in await session.events {
    switch event {
    case .systemInit(let info):
        print("· session \(info.sessionID) — \(info.model)")
    case .assistant(let msg):
        for block in msg.content {
            switch block {
            case .text(let t): print(t)
            case .toolUse(_, let name, let input): print("· tool \(name): \(input)")
            default: break
            }
        }
    case .toolResult(let results):
        for r in results { print("· result (error: \(r.isError))") }
    case .controlRequest(let req):
        if let perm = PermissionRequest(req) {
            print("· auto-allowing \(perm.toolName)")
            await session.respond(to: perm, decision: .allow(updatedInput: perm.input))
        }
    case .result(let r):
        print("· done (cost: \(r.totalCostUSD ?? 0))")
        await session.terminate()
    case .terminated(let code):
        print("· exited \(code)")
    default: break
    }
}
```

- [ ] **Step 5: Verify the probe manually**

Run: `swift run fabled-probe "Reply with exactly: pong"`
Expected: session line, `pong`, done line, exited 0.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: live integration tests and fabled-probe harness"
```

---

## Completion criteria

- `swift test` green offline (no network, no login needed).
- `CLAUDEKIT_LIVE=1 swift test` green (2 live tests) on this machine.
- `swift run fabled-probe "…"` streams a real conversation with auto-allowed permissions.
- Every task committed separately; no red commits.

## Deferred to later plans

- `--include-partial-messages` streaming deltas (Plan 3 needs them for token-by-token rendering; the event decoder's tolerant `.unknown` path already absorbs them safely until then).
- SessionStore / JSONL history parsing (Plan 2).
- Slash-command catalog parsing from the initialize response (Plan 3, composer autocomplete).
- Hook callbacks, MCP message control subtypes (post-v1 unless needed).
