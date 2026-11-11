import AppKit
import ImageIO
import UniformTypeIdentifiers
import CaptureCore
import Darwin

enum ImageInputError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}
enum ImagePreparation {
    static func decode(_ data: Data) throws -> CGImage {
        guard data.count <= 100 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 16384, height <= 16384, width * height <= 64_000_000 else {
            throw ImageInputError.message("Use a single PNG/JPEG image, or a raster image copied to the clipboard (maximum 64 megapixels).")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageInputError.message("The image could not be decoded.")
        }
        return image
    }
    static func png(_ image: CGImage) throws -> Data {
        guard image.width * image.height <= 64_000_000,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: image.width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ImageInputError.message("Image is too large. Crop a smaller area.")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = NSMutableData()
        guard let clean = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageInputError.message("Could not prepare the image.")
        }
        // New pixels + no source properties: never forward EXIF, GPS, comments or file names.
        CGImageDestinationAddImage(destination, clean, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageInputError.message("Could not encode the image.") }
        guard data.length <= AttachmentPolicy.maximumBytes else {
            throw ImageInputError.message("Prepared image exceeds 20 MiB. Crop a smaller area before adding it.")
        }
        return data as Data
    }
    @MainActor static func clipboard(_ board: NSPasteboard) throws -> CGImage {
        if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            guard urls.count == 1, ["png", "jpg", "jpeg"].contains(urls[0].pathExtension.lowercased()),
                  let size = try urls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 100 * 1024 * 1024 else {
                throw ImageInputError.message("Copy one PNG/JPEG file at a time.")
            }
            return try decode(Data(contentsOf: urls[0], options: .mappedIfSafe))
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = board.data(forType: type) { return try decode(data) }
        }
        throw ImageInputError.message("Copy a PNG/JPEG image or an image file, then choose Paste Image.")
    }
    @MainActor static func clipboardHasImage(_ board: NSPasteboard) -> Bool {
        (board.types ?? []).contains { $0 == .png || $0 == .tiff || $0 == .fileURL }
    }
}
final class AttachmentTemporaryStore {
    static var defaultRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CaptureShieldAttachments", isDirectory: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "CaptureShieldLab", isDirectory: true)
    }
    private let directory: URL
    private var lock: Int32 = -1
    init(root: URL = AttachmentTemporaryStore.defaultRoot) throws {
        let files = FileManager.default
        try files.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        Self.cleanAbandoned(in: root)
        directory = root.appendingPathComponent("session-\(UUID())", isDirectory: true)
        try files.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        lock = Darwin.open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            if lock >= 0 { Darwin.close(lock); lock = -1 }
            try? files.removeItem(at: directory)
            throw ImageInputError.message("Could not create private attachment storage.")
        }
    }
    static func cleanAbandoned(in root: URL = defaultRoot) {
        let files = FileManager.default
        for child in (try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [] {
            guard child.lastPathComponent.hasPrefix("session-"), UUID(uuidString: String(child.lastPathComponent.dropFirst(8))) != nil,
                  (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false else { continue }
            let descriptor = Darwin.open(child.appendingPathComponent(".lock").path, O_RDWR | O_NOFOLLOW)
            guard descriptor >= 0 else { continue }
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 { try? files.removeItem(at: child) }
            Darwin.close(descriptor)
        }
    }
    func writePNG(_ data: Data) throws -> URL {
        guard lock >= 0, data.count <= AttachmentPolicy.maximumBytes else {
            throw ImageInputError.message("Attachment storage is closed or the image exceeds 20 MiB.")
        }
        let url = directory.appendingPathComponent("image-\(UUID()).png")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }
    func close() {
        guard lock >= 0 else { return }
        try? FileManager.default.removeItem(at: directory)
        Darwin.close(lock); lock = -1
    }
    deinit { close() }
}
