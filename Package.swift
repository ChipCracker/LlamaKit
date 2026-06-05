// swift-tools-version:6.0
import PackageDescription
import Foundation

// MARK: - llama.xcframework binary target (env-switch: local dev vs. remote release)
//
// • Local mode (default during development): uses the in-tree
//   Frameworks/llama.xcframework (build it via scripts/build-xcframework.sh).
// • Remote mode (for external consumers): set `remoteChecksum` from
//   scripts/package-xcframework.sh and publish the zip as a GitHub release asset.
//
// `useLocal` is true whenever the local xcframework exists, the env var is set,
// or no remote checksum has been published yet → the package builds out of the box.

let remoteURL = "https://github.com/ChipCracker/LlamaKit/releases/download/llama-b9488-2/llama.xcframework.zip"
let remoteChecksum = "90cc7ecc4044c0c54c009714d2c5269b5146bc64204789b3477f061fa72991a4"

// Relativer Pfad fürs binaryTarget (SPM löst ihn ggü. dem Package-Root auf); die
// Existenzprüfung nutzt einen ABSOLUTEN, vom Manifest abgeleiteten Pfad (`#filePath`),
// damit `hasLocal` cwd-unabhängig ist — sonst greift bei Konsum aus einem anderen
// Verzeichnis (Xcode-GUI / xcodebuild aus dem Consumer-Dir) fälschlich das Remote-
// Binary, dem die dSYMs fehlen (DebugSymbolsPath-Validierungsfehler).
let localXCFrameworkPath = "Frameworks/llama.xcframework"
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let localXCFrameworkAbsPath = packageDir + "/" + localXCFrameworkPath
let hasLocalXCFramework = FileManager.default.fileExists(atPath: localXCFrameworkAbsPath)
let forceLocal = ProcessInfo.processInfo.environment["LLAMAKIT_LOCAL_XCFRAMEWORK"] != nil
let useLocal = forceLocal || hasLocalXCFramework || remoteChecksum.isEmpty

let llamaBinaryTarget: Target = useLocal
    ? .binaryTarget(name: "llama", path: localXCFrameworkPath)
    : .binaryTarget(name: "llama", url: remoteURL, checksum: remoteChecksum)

let package = Package(
    name: "LlamaKit",
    platforms: [
        .iOS(.v16),       // xcframework baseline is iOS 16.4 / macOS 13.3
        .macOS(.v13),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "LlamaKit", targets: ["LlamaKit"]),
        .library(name: "LlamaKitTools", targets: ["LlamaKitTools"]),
        .executable(name: "llamakit-cli", targets: ["LlamaKitCLI"]),
    ],
    targets: [
        // Prebuilt llama.cpp xcframework (module `llama`); modulemap already links
        // c++ / Accelerate / Metal / Foundation → no linkerSettings needed here.
        llamaBinaryTarget,

        // Core: engine + context window + tool-calling + model catalog/downloader.
        .target(
            name: "LlamaKit",
            dependencies: ["llama"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // Optional built-in tools (calculator + web search). Kept separate so the
        // core stays dependency-free / offline-capable.
        .target(
            name: "LlamaKitTools",
            dependencies: ["LlamaKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // macOS verification CLI: load a model + run a prompt via `swift run`.
        .executableTarget(
            name: "LlamaKitCLI",
            dependencies: ["LlamaKit", "LlamaKitTools"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(
            name: "LlamaKitTests",
            dependencies: ["LlamaKit", "LlamaKitTools"],
            resources: [.process("Fixtures")]
        ),
    ]
)
