import Foundation

public enum TranscriptionLanguage: String, CaseIterable, Sendable {
    case english = "en-US", chinese = "zh-CN"
    public var title: String { self == .english ? "English" : "中文（普通话）" }
}

public struct TimedSpeechSegment: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let duration: Double
    public init(text: String, start: Double, duration: Double) { self.text = text; self.start = start; self.duration = duration }
}

public enum SpeechAudioPolicy {
    public static let sampleRate = 16000
    public static let maximumSeconds = 120
    public static let maximumSamples = sampleRate * maximumSeconds
    /// 50-second requests with one second of shared context. Boundaries are owned
    /// by exactly one request, using segment midpoints rather than text matching.
    public static func chunks(sampleCount: Int) -> [Range<Int>] {
        let count = min(maximumSamples, max(0, sampleCount))
        var result: [Range<Int>] = [], start = 0
        while start < count {
            let end = min(count, start + 50 * sampleRate)
            result.append(start..<end)
            if end == count { break }
            start = end - sampleRate
        }
        return result
    }
    public static func merge(_ segments: [[TimedSpeechSegment]], chunks: [Range<Int>], language: TranscriptionLanguage) -> String {
        var text: [String] = []
        for (index, chunk) in chunks.enumerated() where index < segments.count {
            let offset = Double(chunk.lowerBound) / Double(sampleRate)
            let lower = offset + (index == 0 ? 0 : 0.5)
            let upper = Double(chunk.upperBound) / Double(sampleRate) - (index == chunks.count - 1 ? 0 : 0.5)
            for segment in segments[index] {
                let midpoint = offset + segment.start + segment.duration / 2
                if midpoint >= lower && midpoint < upper { text.append(segment.text) }
            }
        }
        return text.joined(separator: language == .english ? " " : "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct SpeechSessionState: Sendable {
    public enum Phase: String, Sendable { case idle, preparing, recording, transcribing, ready }
    public private(set) var phase: Phase = .idle
    public private(set) var generation = 0
    public init() {}
    @discardableResult public mutating func begin() -> Int? {
        guard phase == .idle else { return nil }
        generation += 1; phase = .preparing; return generation
    }
    public mutating func transition(_ phase: Phase, generation: Int) -> Bool {
        guard self.generation == generation else { return false }
        self.phase = phase; return true
    }
    public mutating func reset() { generation += 1; phase = .idle }
}
