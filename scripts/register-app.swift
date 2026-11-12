// Register the freshly signed bundle so TCC/System Settings can resolve its ID.
// This does not grant or reset any privacy permission.
import AppKit
import CoreServices

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: register-app.swift /absolute/Application.app [...]\n", stderr)
    exit(2)
}
for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    guard url.pathExtension == "app", let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else {
        fputs("Not a valid application bundle: \(path)\n", stderr); exit(2)
    }
    let result = LSRegisterURL(url as CFURL, true)
    guard result == noErr else {
        fputs("Application registration failed (\(result)): \(identifier)\n", stderr); exit(1)
    }
    guard let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
          found.resolvingSymlinksInPath().standardizedFileURL == url else {
        fputs("The system could not resolve this build by its bundle ID: \(identifier). Use a persistent local app folder and check for duplicate builds.\n", stderr); exit(1)
    }
    print("Registered \(identifier)")
}
