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
            // A prompt line past the scan window can still be decoded when the
            // byte filter fires (title-key bytes elsewhere on a user line);
            // never let it become the first-prompt fallback.
            if case .userPrompt = entry, !parseForPrompt { continue }
            accumulator.consume(entry)
        }
        return accumulator.best
    }

    static func containsTitleKey(_ line: Data) -> Bool {
        titleKeyPatterns.contains { line.range(of: $0) != nil }
    }
}
