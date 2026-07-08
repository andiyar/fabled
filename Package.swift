// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ClaudeKit", targets: ["ClaudeKit"]),
        .executable(name: "fabled-probe", targets: ["fabled-probe"]),
    ],
    targets: [
        .target(name: "ClaudeKit"),
        .executableTarget(name: "fabled-probe", dependencies: ["ClaudeKit"]),
        .testTarget(name: "ClaudeKitTests", dependencies: ["ClaudeKit"]),
    ]
)
