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
