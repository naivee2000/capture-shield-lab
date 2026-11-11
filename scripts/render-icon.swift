// Editable vector source for the original CaptureShield icon.
// Run: xcrun swift scripts/render-icon.swift Assets
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Assets", isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let iconset = output.appendingPathComponent("CaptureShield.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let shield = "M 512 146 L 794 250 L 774 500 C 762 673 650 798 512 878 C 374 798 262 673 250 500 L 230 250 Z"
let window = "M 356 348 L 668 348 L 668 590 L 356 590 Z"
let divider = "M 356 412 L 668 412"
let teal = NSColor(srgbRed: 0.24, green: 0.87, blue: 0.75, alpha: 1)
func path(_ source: String) -> NSBezierPath {
    let tokens = source.split(separator: " ").map(String.init)
    let result = NSBezierPath(); var i = 0
    func point() -> NSPoint {
        let x = Double(tokens[i])!, y = Double(tokens[i + 1])!; i += 2
        return NSPoint(x: x, y: y)
    }
    while i < tokens.count {
        let command = tokens[i]; i += 1
        switch command {
        case "M": result.move(to: point())
        case "L": result.line(to: point())
        case "C": let a = point(), b = point(), end = point(); result.curve(to: end, controlPoint1: a, controlPoint2: b)
        case "Z": result.close()
        default: fatalError("Unsupported icon path command")
        }
    }
    result.lineJoinStyle = .round; result.lineCapStyle = .round
    return result
}
func render(_ size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let transform = NSAffineTransform(); transform.translateX(by: 0, yBy: CGFloat(size))
    transform.scaleX(by: CGFloat(size) / 1024, yBy: -CGFloat(size) / 1024); transform.concat()
    NSColor(srgbRed: 0.035, green: 0.055, blue: 0.08, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 210, yRadius: 210).fill()
    let outline = path(shield)
    NSColor(srgbRed: 0.055, green: 0.19, blue: 0.20, alpha: 1).setFill(); outline.fill()
    teal.setStroke(); outline.lineWidth = 42; outline.stroke()
    let pane = path(window); NSColor(srgbRed: 0.68, green: 0.97, blue: 0.91, alpha: 1).setStroke()
    pane.lineWidth = 24; pane.stroke()
    let line = path(divider); line.lineWidth = 20; line.stroke()
    teal.setFill(); NSBezierPath(ovalIn: NSRect(x: 382, y: 369, width: 20, height: 20)).fill()
    NSBezierPath(ovalIn: NSRect(x: 420, y: 369, width: 20, height: 20)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(points * scale).write(to: iconset.appendingPathComponent(name))
    }
}
try render(1024).write(to: output.appendingPathComponent("CaptureShield.png"))
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<rect x="32" y="32" width="960" height="960" rx="210" fill="#090e14"/>
<path d="\(shield)" fill="#0e3033" stroke="#3ddfc0" stroke-width="42" stroke-linejoin="round"/>
<path d="\(window)" fill="none" stroke="#adf7e8" stroke-width="24" stroke-linejoin="round"/>
<path d="\(divider)" fill="none" stroke="#adf7e8" stroke-width="20"/>
<g fill="#3ddfc0"><circle cx="392" cy="379" r="10"/><circle cx="430" cy="379" r="10"/></g>
</svg>
"""
try svg.write(to: output.appendingPathComponent("CaptureShield.svg"), atomically: true, encoding: .utf8)
let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("CaptureShield.icns").path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { exit(task.terminationStatus) }
// Only the generated files in this dedicated iconset directory are removed.
try FileManager.default.removeItem(at: iconset)
print("Generated CaptureShield.svg, .png and .icns in \(output.path)")
