// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CaptureShieldLab",
    platforms: [.macOS("15.6")],
    products: [
        .executable(name: "CaptureShieldLab", targets: ["CaptureShieldLab"]),
        .executable(name: "CaptureProbe", targets: ["CaptureProbe"])
    ],
    targets: [
        .target(name: "CaptureCore"),
        .executableTarget(name: "CaptureShieldLab", dependencies: ["CaptureCore"], linkerSettings: [
            // SDK 26.2 imports the new screenshot classes as strong references
            // despite our #available guard. Weak-link so macOS 15 can load the
            // process before choosing CompatibleScreenshotBackend. ScreenCaptureKit
            // itself exists on every supported OS; modern calls stay version-gated.
            .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "ScreenCaptureKit"])
        ]),
        .executableTarget(name: "CaptureProbe", dependencies: ["CaptureCore"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"]),
        .testTarget(name: "CaptureWindowTests", dependencies: ["CaptureShieldLab", "CaptureCore"])
    ]
)
