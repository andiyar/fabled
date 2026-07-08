import Foundation
import ClaudeKit

// Usage: fabled-probe [--model X] [--cwd DIR] "prompt"
// Streams events to stdout; auto-allows all permission requests. Manual harness only.
var args = Array(CommandLine.arguments.dropFirst())
var config = SessionConfiguration(
    workingDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
config.model = "haiku"

while args.count >= 2, args[0].hasPrefix("--") {
    switch args[0] {
    case "--model": config.model = args[1]
    case "--cwd": config.workingDirectory = URL(fileURLWithPath: args[1])
    default: FileHandle.standardError.write(Data("unknown flag \(args[0])\n".utf8))
    }
    args.removeFirst(2)
}
guard let prompt = args.first else {
    print("usage: fabled-probe [--model X] [--cwd DIR] \"prompt\"")
    exit(1)
}

let session = AgentSession(configuration: config)
try await session.start()
await session.send(prompt)

for await event in await session.events {
    switch event {
    case .systemInit(let info):
        print("· session \(info.sessionID) — \(info.model)")
    case .assistant(let msg):
        for block in msg.content {
            switch block {
            case .text(let t): print(t)
            case .toolUse(_, let name, let input): print("· tool \(name): \(input)")
            default: break
            }
        }
    case .toolResult(let results):
        for r in results { print("· result (error: \(r.isError))") }
    case .controlRequest(let req):
        if let perm = PermissionRequest(req) {
            print("· auto-allowing \(perm.toolName)")
            await session.respond(to: perm, decision: .allow(updatedInput: perm.input))
        }
    case .result(let r):
        print("· done (cost: \(r.totalCostUSD ?? 0))")
        await session.terminate()
    case .terminated(let code):
        print("· exited \(code)")
    default: break
    }
}
