import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import CaptureCore

@MainActor
final class ShieldView: NSView {
    private var shield: AVSampleBufferDisplayLayer?
    private(set) var mode: ProtectionMode = .ordinary
    private(set) var failure: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(srgbRed: 0.045, green: 0.075, blue: 0.14, alpha: 1).cgColor
        layer?.cornerRadius = 18
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ mode: ProtectionMode) {
        isHidden = true
        self.mode = mode; failure = nil
        layer?.mask = nil; shield = nil
        guard mode.usesMask else { isHidden = false; return }
        do {
            let mask = AVSampleBufferDisplayLayer()
            mask.videoGravity = .resize
            mask.preventsCapture = mode == .protectedMask
            mask.frame = bounds
            mask.sampleBufferRenderer.enqueue(try Self.opaqueFrame())
            shield = mask
            layer?.mask = mask
            if let error = healthError { throw ShieldError.message(error) }
            isHidden = false
        } catch { failClosed(error.localizedDescription) }
    }

    var healthError: String? {
        if let failure { return failure }
        guard mode.usesMask else { return nil }
        guard let renderer = shield?.sampleBufferRenderer else { return "Mask renderer is missing." }
        if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
            return renderer.error?.localizedDescription ?? "Renderer requires recovery; rerun this mode."
        }
        return nil
    }

    func failClosed(_ reason: String) {
        isHidden = true
        failure = reason
        // Never remove protection or substitute an unprotected view on failure.
    }
    override func layout() {
        super.layout()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        shield?.frame = bounds
        CATransaction.commit()
    }

    private static func opaqueFrame() throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, attrs, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { throw ShieldError.message("Cannot allocate mask pixels.") }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            throw ShieldError.message("Cannot lock mask pixels.")
        }
        guard let address = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw ShieldError.message("Missing mask pixel memory.")
        }
        let bytes = address.assumingMemoryBound(to: UInt8.self)
        for row in 0..<16 { for col in 0..<16 {
            let i = row * CVPixelBufferGetBytesPerRow(pixelBuffer) + col * 4
            bytes[i] = 0; bytes[i + 1] = 0; bytes[i + 2] = 0; bytes[i + 3] = 255
        } }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescriptionOut: &format) == noErr, let format else {
            throw ShieldError.message("Cannot describe mask pixels.")
        }
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else {
            throw ShieldError.message("Cannot create mask sample.")
        }
        if let array = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            array.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }
}

enum ShieldError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}
