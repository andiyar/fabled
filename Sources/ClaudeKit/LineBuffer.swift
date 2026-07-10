import Foundation

/// Incremental NDJSON line assembly for pipe chunks. Pipes deliver arbitrary
/// splits — macOS pipe writes fragment well below real event-line sizes — so
/// lines routinely arrive split mid-line (and mid-UTF-8 sequence) across
/// chunks. This buffers chunks and emits only complete lines.
struct LineBuffer {
    private var buffer = Data()

    /// Appends a chunk and returns every complete newline-terminated line in
    /// the buffer, without their newlines. Empty lines are skipped. Returned
    /// lines are copied out so they do not pin the accumulating buffer.
    mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            if !line.isEmpty { lines.append(Data(line)) }
            buffer.removeSubrange(...newline)
        }
        return lines
    }

    /// The unterminated remainder at EOF, nil if none. NDJSON is
    /// newline-terminated in practice, but a final line missing its newline
    /// should still be offered to the decoder rather than dropped silently.
    mutating func finish() -> Data? {
        defer { buffer.removeAll() }
        return buffer.isEmpty ? nil : buffer
    }
}
