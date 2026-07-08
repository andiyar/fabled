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

        Task.detached {
            let handle = stderr.fileHandleForReading
            while let chunk = try? handle.read(upToCount: 65536), !chunk.isEmpty {}
        }

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
