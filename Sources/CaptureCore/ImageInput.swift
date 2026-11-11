import Foundation
import CoreGraphics

public enum WindowDirection: Sendable { case up, down, left, right }
extension WindowPlacement {
    public static func moved(_ frame: CGRect, direction: WindowDirection, visibleFrame: CGRect) -> CGRect {
        var next = frame
        switch direction {
        case .up: next.origin.y += 40
        case .down: next.origin.y -= 40
        case .left: next.origin.x -= 40
        case .right: next.origin.x += 40
        }
        return restore(next, screens: [visibleFrame])
    }
}
public enum ImageGeometry {
    /// Both input rectangles use a top-left origin, independent of AppKit screen coordinates.
    public static func pixelCrop(selection: CGRect, imageRect: CGRect, pixels: CGSize) -> CGRect? {
        guard [selection.minX, selection.minY, selection.width, selection.height,
               imageRect.minX, imageRect.minY, imageRect.width, imageRect.height,
               pixels.width, pixels.height].allSatisfy(\.isFinite),
              !imageRect.isEmpty, pixels.width > 0, pixels.height > 0 else { return nil }
        let rect = selection.standardized.intersection(imageRect)
        guard !rect.isNull, !rect.isEmpty else { return nil }
        let x = (rect.minX - imageRect.minX) / imageRect.width * pixels.width
        let y = (rect.minY - imageRect.minY) / imageRect.height * pixels.height
        return CGRect(x: x, y: y, width: rect.width / imageRect.width * pixels.width,
                      height: rect.height / imageRect.height * pixels.height).integral
            .intersection(CGRect(origin: .zero, size: pixels))
    }
}
public enum AttachmentPolicy {
    public static let maximumBytes = 20 * 1024 * 1024
    public static func allows(_ url: URL?, preview: Bool = false) -> Bool {
        guard let url else { return false }
        if preview { return url.absoluteString == "about:blank" }
        guard url.scheme == "https", url.host?.lowercased() == "chatgpt.com", url.port == nil || url.port == 443,
              url.user == nil, url.password == nil else { return false }
        let path = url.path.removingPercentEncoding ?? url.path
        let segment = path.split(separator: "/").first.map(String.init)?.lowercased() ?? ""
        return !["auth", "login", "signup", "settings"].contains(segment)
    }
}
public struct AttachmentConsent {
    private var document: String?
    public init() {}
    public mutating func arm(document: String) { self.document = document }
    public mutating func cancel() { document = nil }
    public mutating func consume(document: String) -> Bool {
        defer { self.document = nil }
        return self.document == document
    }
}
