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
