import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import ImageIO
import UniformTypeIdentifiers
import CaptureCore

struct CapturedFrame: Sendable {
    let sequence: Int
    let presentation: Double
    let pixels: PixelFrame
}

/// ScreenCaptureKit calls on a serial sample queue. Only this lock-protected inbox crosses actors.
final class FrameInbox: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CapturedFrame?
    private var sequence = 0
    private var error: String?
    private let region: CGRect
    private let expectedWidth: Int
    private let expectedHeight: Int

    init(region: CGRect, width: Int, height: Int) {
        self.region = region; expectedWidth = width; expectedHeight = height
    }
    func snapshot() -> (CapturedFrame?, String?) { lock.withLock { (latest, error) } }
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        lock.withLock { self.error = error.localizedDescription }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        guard status == .complete else {
            if status == .blank || status == .suspended || status == .stopped {
                lock.withLock { error = "Capture stream produced an unusable frame (status \(raw))." }
            }
            return
        }
        guard let buffer = sampleBuffer.imageBuffer,
              CVPixelBufferGetWidth(buffer) == expectedWidth,
              CVPixelBufferGetHeight(buffer) == expectedHeight,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
            lock.withLock { error = "Unexpected frame format or dimensions; coordinate mapping is invalid." }; return
        }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let src = base.assumingMemoryBound(to: UInt8.self)
        let x = Int(region.minX), y = Int(region.minY), width = Int(region.width), height = Int(region.height)
        guard x >= 0, y >= 0, x + width <= expectedWidth, y + height <= expectedHeight else {
            lock.withLock { error = "Test region moved outside the captured display." }; return
        }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height { for col in 0..<width {
            let s = (y + row) * stride + (x + col) * 4
            let d = (row * width + col) * 4
            rgba[d] = src[s + 2]; rgba[d + 1] = src[s + 1]; rgba[d + 2] = src[s]
        } }
        let displayTime = attachments.first?[.displayTime] as? UInt64
        let presentation = displayTime.map { CMTimeGetSeconds(CMClockMakeHostTimeFromSystemUnits($0)) }
            ?? CMTimeGetSeconds(sampleBuffer.presentationTimeStamp)
        lock.withLock {
            sequence += 1
            latest = CapturedFrame(sequence: sequence, presentation: presentation,
                                   pixels: PixelFrame(width: width, height: height, rgba: rgba))
        }
    }
}

@MainActor
final class ScreenStream {
    let inbox: FrameInbox
    private let stream: SCStream
    private var consumedSequence = 0
    private var notBefore: Double = 0
    private let sampleQueue = DispatchQueue(label: "dev.naivee2000.captureshield.samples")

    init(display: SCDisplay, region: CGRect, width: Int, height: Int) throws {
        inbox = FrameInbox(region: region, width: width, height: height)
        // Deliberately exclude NOTHING: the recorder must not manufacture a pass.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = width; config.height = height
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.capturesAudio = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 5)
        config.queueDepth = 3
        stream = SCStream(filter: filter, configuration: config, delegate: inbox)
        try stream.addStreamOutput(inbox, type: .screen, sampleHandlerQueue: sampleQueue)
    }
    func start() async throws { try await stream.startCapture() }
    func stop() async { try? await stream.stopCapture() }
    /// Fresh frames only: never count cached images or a denied stream as evidence.
    func nextFrame() async throws -> PixelFrame {
        for _ in 0..<60 {
            try Task.checkCancellation()
            let (frame, error) = inbox.snapshot()
            if let error { throw ProbeError.message(error) }
            if let frame, EvidenceGate.acceptsFrame(presentation: frame.presentation, notBefore: notBefore,
                                                    sequence: frame.sequence, after: consumedSequence) {
                consumedSequence = frame.sequence; return frame.pixels
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw ProbeError.message("No fresh complete screen frames arrived. Check permission and relaunch CaptureProbe.")
    }
    func discardQueuedFrames() {
        consumedSequence = inbox.snapshot().0?.sequence ?? 0
        notBefore = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) + 0.2
    }
}

enum ProbeError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

func savePNG(_ frame: PixelFrame, to url: URL) throws {
    guard let provider = CGDataProvider(data: Data(frame.rgba) as CFData),
          let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: frame.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                              decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw ProbeError.message("Cannot create evidence image.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw ProbeError.message("Cannot write evidence image.") }
}
