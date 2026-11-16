import Foundation
import Testing

/// A native host for SwiftPM's built test bundle. On Darwin, SwiftPM ignores
/// --experimental-test-entry-point-path. Load the same bundle without invoking
/// its generated async main, then run the same built-in Testing entry point.
/// See swiftlang/swift#91716: a stopped CF run loop must not imply success.
@main struct NativeTestMain {
    @MainActor static func main() {
        guard let json = ProcessInfo.processInfo.environment["CAPTURESHIELD_NATIVE_BUNDLES"],
              let paths = try? JSONDecoder().decode([String].self, from: Data(json.utf8)), !paths.isEmpty else {
            FileHandle.standardError.write(Data("Missing native test bundles.\n".utf8)); exit(2)
        }
        setenv("CAPTURESHIELD_NATIVE_HOST", "1", 1)
        for path in paths {
            guard path.hasSuffix(".xctest"), let bundle = Bundle(path: path) else {
                FileHandle.standardError.write(Data("Native test bundle failed to load.\n".utf8)); exit(2)
            }
            do { try bundle.loadAndReturnError() }
            catch {
                FileHandle.standardError.write(Data("Native test bundle load error: \(error.localizedDescription)\n".utf8)); exit(2)
            }
        }
        var arguments = Testing.__CommandLineArguments_v0()
        arguments.parallel = false
        var iterator = CommandLine.arguments.dropFirst().makeIterator()
        while let flag = iterator.next() {
            switch flag {
            case "--filter": arguments.filter = (arguments.filter ?? []) + [iterator.next() ?? "(?!)"]
            case "--skip": arguments.skip = (arguments.skip ?? []) + [iterator.next() ?? "(?!)"]
            case "--parallel": arguments.parallel = true
            case "--no-parallel": arguments.parallel = false
            default: FileHandle.standardError.write(Data("Unknown native test option.\n".utf8)); exit(2)
            }
        }
        let keepAlive = Timer(timeInterval: 3600, repeats: true) { _ in }
        RunLoop.main.add(keepAlive, forMode: .common)
        Task { @MainActor [arguments] in await Testing.__swiftPMEntryPoint(passing: arguments) as Never }
        while true { autoreleasepool { CFRunLoopRun() } }
    }
}
