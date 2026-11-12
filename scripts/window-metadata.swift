// Read-only diagnostic: no window titles, input text, screenshots or account data.
// Run before/during/after a synthetic candidate popup; keep output outside Git.
import AppKit
import CoreGraphics

let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
let result: [[String: Any]] = rows.compactMap { row in
    guard let pid = row[kCGWindowOwnerPID as String] as? Int32 else { return nil }
    return ["windowID": row[kCGWindowNumber as String] ?? 0,
            "pid": pid,
            "bundleID": NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "unknown",
            "layer": row[kCGWindowLayer as String] ?? 0,
            "bounds": row[kCGWindowBounds as String] ?? [:]]
}
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted])
print(String(decoding: data, as: UTF8.self))
