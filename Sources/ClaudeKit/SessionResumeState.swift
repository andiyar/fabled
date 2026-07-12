import Foundation

/// The model and permission mode a session was last operating in, recovered
/// from its on-disk transcript so a resume can restore them (UX-LEDGER row 15
/// — "the model goes to default… I don't even know what the last model was").
///
/// Both are read straight from the persisted lines, so this works for sessions
/// Fabled never spawned (e.g. Claude Desktop's) as well as its own. Absent
/// fields stay nil; the caller falls back to the spawn defaults.
public struct SessionResumeState: Sendable, Equatable {
    /// Last assistant model id (`message.model`), e.g. `claude-opus-4-8`.
    public var model: String?
    /// Last permission mode the transcript recorded — a top-level field that
    /// `user` lines carry every prompt (`default`/`plan`/`acceptEdits`/
    /// `bypassPermissions`, and Claude Desktop's `auto`).
    public var permissionMode: String?

    public init(model: String? = nil, permissionMode: String? = nil) {
        self.model = model
        self.permissionMode = permissionMode
    }

    /// Single pass over the raw file bytes (same approach as
    /// `SessionTitle.derive`): last non-empty value wins for each field.
    public static func derive(fromFileData data: Data) -> SessionResumeState {
        var state = SessionResumeState()
        for line in JSONLines(data: data) {
            guard let raw = try? JSONValue(parsing: line) else { continue }
            if raw["type"]?.stringValue == "assistant",
               let model = raw["message"]?["model"]?.stringValue, !model.isEmpty {
                state.model = model
            }
            if let mode = raw["permissionMode"]?.stringValue, !mode.isEmpty {
                state.permissionMode = mode
            }
        }
        return state
    }
}
