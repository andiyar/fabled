import ClaudeKit
import Foundation

/// Display formatting for JSONValue payloads in tool cards and raw views.
public enum JSONPretty {
    public static func string(_ value: JSONValue) -> String {
        // Bare strings read better unquoted (tool results are usually text).
        if let text = value.stringValue { return text }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
