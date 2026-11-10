import Foundation
import CoreGraphics

public struct PixelFrame: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]
    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width; self.height = height; self.rgba = rgba
    }
    public var isValid: Bool {
        width > 0 && height > 0 && width <= 32768 && height <= 32768 && rgba.count == width * height * 4
    }
}

public enum AnalysisError: Error { case invalidFrame, invalidRegion }
public struct Comparison: Sendable {
    public let mismatchFraction: Double
    public let meanError: Double
    public var matchesBackground: Bool { mismatchFraction <= 0.0005 && meanError <= 1.5 }
}
public enum CaptureAnalysis {
    public static func compare(_ frame: PixelFrame, to baseline: PixelFrame) throws -> Comparison {
        guard frame.isValid, baseline.isValid, frame.width == baseline.width, frame.height == baseline.height else {
            throw AnalysisError.invalidFrame
        }
        var different = 0, sum = 0
        for i in stride(from: 0, to: frame.rgba.count, by: 4) {
            var maximum = 0
            for c in 0..<3 {
                let delta = abs(Int(frame.rgba[i + c]) - Int(baseline.rgba[i + c]))
                sum += delta; maximum = max(maximum, delta)
            }
            if maximum > 16 { different += 1 }
        }
        let count = Double(frame.width * frame.height)
        return Comparison(mismatchFraction: Double(different) / count, meanError: Double(sum) / (count * 3))
    }
    public static func isUsefulBaseline(_ frame: PixelFrame) -> Bool {
        guard frame.isValid else { return false }
        var dark = 0, light = 0
        for i in stride(from: 0, to: frame.rgba.count, by: 4) {
            let average = (Int(frame.rgba[i]) + Int(frame.rgba[i + 1]) + Int(frame.rgba[i + 2])) / 3
            if average < 110 { dark += 1 }
            if average > 145 { light += 1 }
        }
        let total = frame.width * frame.height
        return dark > total / 5 && light > total / 5
    }
    public static func pixelRect(window: CGRect, display: CGRect, pixelWidth: Int, pixelHeight: Int) throws -> CGRect {
        let values = [window.minX, window.minY, window.width, window.height, display.minX, display.minY, display.width, display.height]
        guard values.allSatisfy(\.isFinite), window.width > 0, window.height > 0,
              display.width > 0, display.height > 0, display.contains(window),
              pixelWidth > 0, pixelHeight > 0, pixelWidth <= 32768, pixelHeight <= 32768 else { throw AnalysisError.invalidRegion }
        let sx = Double(pixelWidth) / display.width, sy = Double(pixelHeight) / display.height
        let x = floor((window.minX - display.minX) * sx)
        let y = floor((window.minY - display.minY) * sy)
        let right = ceil((window.maxX - display.minX) * sx)
        let bottom = ceil((window.maxY - display.minY) * sy)
        guard x >= 0, y >= 0, right <= Double(pixelWidth), bottom <= Double(pixelHeight) else { throw AnalysisError.invalidRegion }
        return CGRect(x: x, y: y, width: right - x, height: bottom - y)
    }
}
public enum Verdict: String, Codable, Sendable { case pass, fail, notTested = "not-tested" }
public enum Outcome {
    public static func candidate(frames: [Comparison], controlsVisible: Bool, localConfirmed: Bool?) -> Verdict {
        guard controlsVisible, !frames.isEmpty else { return .notTested }
        guard frames.allSatisfy(\.matchesBackground) else { return .fail }
        guard let localConfirmed else { return .notTested }
        return localConfirmed ? .pass : .fail
    }
}
