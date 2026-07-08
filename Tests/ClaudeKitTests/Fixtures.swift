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
