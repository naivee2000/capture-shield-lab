import Testing
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import CaptureShieldLab

@MainActor struct ImagePipelineTests {
    static func fixture(orientation: Int = 1) -> Data {
        let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 80,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Synthetic metadata"]] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
    @Test func decoderAppliesOrientationAndEncoderOmitsPrivateMetadata() throws {
        let image = try ImagePreparation.decode(Self.fixture(orientation: 6))
        #expect(image.width == 10 && image.height == 20)
        let png = try ImagePreparation.png(image)
        let source = CGImageSourceCreateWithData(png as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        let exif = properties[kCGImagePropertyExifDictionary] as? NSDictionary
        #expect(exif?[kCGImagePropertyExifUserComment] == nil)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }
    @Test func invalidImageIsRejected() {
        #expect(throws: (any Error).self) { try ImagePreparation.decode(Data("not an image".utf8)) }
    }
    @Test func largeEncodedImageRequiresCropping() throws {
        var pixels = Data(count: 4000 * 2000 * 4)
        pixels.withUnsafeMutableBytes { buffer in arc4random_buf(buffer.baseAddress!, buffer.count) }
        let provider = CGDataProvider(data: pixels as CFData)!
        let image = CGImage(width: 4000, height: 2000, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16000,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        do { _ = try ImagePreparation.png(image); Issue.record("Oversized PNG was accepted") }
        catch { #expect(error.localizedDescription.contains("20 MiB")) }
    }
    @Test func temporaryFilesSurviveOtherActiveStoresButAreRemovedOnClose() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("image-store-test-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try AttachmentTemporaryStore(root: root)
        let file = try first.writePNG(Self.fixture())
        #expect(FileManager.default.fileExists(atPath: file.path))
        let second = try AttachmentTemporaryStore(root: root)
        #expect(FileManager.default.fileExists(atPath: file.path))
        first.close(); second.close()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
