import Foundation

public enum PermissionDecision: Sendable, Equatable {
    /// `updatedInput: nil` means "run with the input exactly as requested".
    /// The CLI *requires* the `updatedInput` field (Zod-validated; omitting
    /// it denies the tool — fixtures/2026-07-09-perm-allow-noinput.jsonl),
    /// so encoding substitutes the request's own input.
    /// `updatedPermissions`: pass the request's `permission_suggestions`
    /// entries verbatim to persist an always-allow rule (the CLI writes it
    /// to the suggestion's `destination`).
    case allow(updatedInput: JSONValue?, updatedPermissions: [JSONValue]?)
    case deny(message: String?)

    /// Plain approval: original input, no persisted rules.
    public static let allowAsRequested = PermissionDecision.allow(
        updatedInput: nil, updatedPermissions: nil)
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
        requestID: String, decision: PermissionDecision, requestedInput: JSONValue
    ) -> Data {
        var inner: [String: JSONValue]
        switch decision {
        case .allow(let updatedInput, let updatedPermissions):
            inner = [
                "behavior": .string("allow"),
                "updatedInput": updatedInput ?? requestedInput,
            ]
            if let updatedPermissions, !updatedPermissions.isEmpty {
                inner["updatedPermissions"] = .array(updatedPermissions)
            }
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
