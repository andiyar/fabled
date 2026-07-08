// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ClaudeKit", targets: ["ClaudeKit"]),
        .library(name: "FabledCore", targets: ["FabledCore"]),
        .executable(name: "fabled-probe", targets: ["fabled-probe"]),
    ],
    targets: [
        .target(name: "ClaudeKit"),
        .target(name: "FabledCore", dependencies: ["ClaudeKit"]),
        .executableTarget(name: "fabled-probe", dependencies: ["ClaudeKit"]),
        .testTarget(name: "ClaudeKitTests", dependencies: ["ClaudeKit"]),
        .testTarget(name: "FabledCoreTests", dependencies: ["FabledCore"]),
    ]
)
