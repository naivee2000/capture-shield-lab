// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CaptureShieldLab",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "CaptureShieldLab", targets: ["CaptureShieldLab"]),
        .executable(name: "CaptureProbe", targets: ["CaptureProbe"])
    ],
    targets: [
        .target(name: "CaptureCore"),
        .executableTarget(name: "CaptureShieldLab", dependencies: ["CaptureCore"]),
        .executableTarget(name: "CaptureProbe", dependencies: ["CaptureCore"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"])
    ]
)
