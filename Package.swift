// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Nagi",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure, side-effect-isolated logic (file writing, persistence, editor
        // state transitions). Knows nothing about AppKit or SwiftUI.
        .target(
            name: "NagiCore",
            path: "Sources/NagiCore"
        ),
        // The UI layer: views, the capture panel, the global hotkey, and the
        // orchestration that turns a keystroke into a core transition.
        // A library rather than part of the executable so its orchestration can
        // be unit-tested; only `@main` lives in the executable.
        .target(
            name: "NagiUI",
            dependencies: ["NagiCore"],
            path: "Sources/NagiUI"
        ),
        .executableTarget(
            name: "Nagi",
            dependencies: ["NagiUI", "NagiCore"],
            path: "Sources/Nagi"
        ),
        .testTarget(
            name: "NagiCoreTests",
            dependencies: ["NagiCore"],
            path: "Tests/NagiCoreTests"
        ),
        .testTarget(
            name: "NagiUITests",
            dependencies: ["NagiUI", "NagiCore"],
            path: "Tests/NagiUITests"
        ),
    ]
)
