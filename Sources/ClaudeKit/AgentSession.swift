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
    private var isTerminated = false

    /// Single-consumer stream of everything the CLI emits, plus `.terminated`.
    public private(set) var events: AsyncStream<AgentEvent> = AsyncStream { $0.finish() }

    /// Fixed id for the initialize handshake so consumers can correlate the
    /// CLI's catalog response (commands, models, account) without plumbing.
    /// One id per process is safe: each AgentSession owns its own child.
    public static let initializeRequestID = "init"

    public init(configuration: SessionConfiguration) {
        self.configuration = configuration
    }

    /// Terminating via `terminate()` is the intended path; this is the
    /// safety net for a dropped session. Dropping a Continuation does NOT
    /// finish its stream (Plan 2 scar) — finish explicitly or a consumer
    /// awaiting `events` hangs forever on a dead session.
    deinit {
        process?.terminate()
        readTask?.cancel()
        continuation?.finish()
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
            continuation.finish()
            self.continuation = nil
            throw SessionError.launchFailed(String(describing: error))
        }
        self.process = process
        self.stdinPipe = stdin

        // Pipe reads MUST happen on dedicated threads, never the cooperative
        // pool: a blocking read() parks its pool thread indefinitely, and with
        // a few sessions open the pool exhausts — later sessions' readers then
        // never get scheduled and their children look silent (2026-07-10 bug:
        // intermittent "Starting Claude…" hangs / invisible conversations;
        // repro was 3 staggered spawns — only the first ever spoke).
        let stderrHandle = stderr.fileHandleForReading
        Thread.detachNewThread {
            // Drained and discarded — an unread stderr pipe would eventually
            // block the child once the buffer fills.
            while !stderrHandle.availableData.isEmpty {}
        }

        let stdoutHandle = stdout.fileHandleForReading
        let (chunks, chunkContinuation) = AsyncStream.makeStream(of: Data.self)
        Thread.detachNewThread {
            while true {
                let chunk = stdoutHandle.availableData // blocks on the dedicated thread
                if chunk.isEmpty {
                    chunkContinuation.finish()
                    return
                }
                chunkContinuation.yield(chunk)
            }
        }

        readTask = Task { [weak self] in
            var buffer = Data()
            for await chunk in chunks {
                guard let self else { return }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let lineData = buffer.prefix(upTo: newline)
                    buffer.removeSubrange(...newline)
                    guard !lineData.isEmpty else { continue }
                    if let event = try? AgentEventDecoder.decode(lineData) {
                        await self.emit(event)
                    }
                }
            }
            // Pipe closed — termination handler emits .terminated.
        }

        write(Outbound.initialize(requestID: Self.initializeRequestID))
    }

    public func send(_ text: String) {
        write(Outbound.userMessage(text))
    }

    public func respond(to request: PermissionRequest, decision: PermissionDecision) {
        write(Outbound.permissionResponse(requestID: request.requestID,
                                          decision: decision,
                                          requestedInput: request.input))
    }

    @discardableResult
    public func interrupt() -> String {
        sendControl(subtype: "interrupt")
    }

    @discardableResult
    public func setModel(_ model: String) -> String {
        sendControl(subtype: "set_model", extra: ["model": .string(model)])
    }

    @discardableResult
    public func setPermissionMode(_ mode: String) -> String {
        sendControl(subtype: "set_permission_mode", extra: ["mode": .string(mode)])
    }

    public func terminate() {
        // Short-circuit writes immediately: between an intentional terminate()
        // and handleTermination the pipe can die and a write would SIGPIPE.
        isTerminated = true
        process?.terminate()
    }

    private func sendControl(subtype: String, extra: [String: JSONValue] = [:]) -> String {
        let requestID = UUID().uuidString
        write(Outbound.controlRequest(
            requestID: requestID, subtype: subtype, extra: extra))
        return requestID
    }

    private func write(_ data: Data) {
        // After child death the pipe write raises SIGPIPE, which `try?`
        // cannot swallow (it is a signal, not an error) — short-circuit.
        guard !isTerminated else { return }
        try? stdinPipe?.fileHandleForWriting.write(contentsOf: data)
    }

    private func emit(_ event: AgentEvent) {
        continuation?.yield(event)
    }

    private func handleTermination(exitCode: Int32) async {
        isTerminated = true
        await readTask?.value
        continuation?.yield(.terminated(exitCode: exitCode))
        continuation?.finish()
        continuation = nil
        readTask = nil
    }

}
