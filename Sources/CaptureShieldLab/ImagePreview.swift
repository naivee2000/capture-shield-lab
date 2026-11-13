import AppKit
import CaptureCore

@MainActor final class CropCanvas: NSView {
    let image: CGImage
    private var start: CGPoint?
    private var selection: CGRect?
    override var isFlipped: Bool { true }
    init(image: CGImage) {
        self.image = image; super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityLabel("Image crop preview. Drag a rectangle to crop.")
        setAccessibilityIdentifier("crop-canvas")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    var imageRect: CGRect {
        let size = CGSize(width: image.width, height: image.height)
        let scale = min(max(1, bounds.width - 24) / size.width, max(1, bounds.height - 24) / size.height)
        return CGRect(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2,
                      width: size.width * scale, height: size.height * scale)
    }
    var croppedImage: CGImage {
        guard let selection, let rect = ImageGeometry.pixelCrop(selection: selection, imageRect: imageRect,
                pixels: CGSize(width: image.width, height: image.height)),
              let cropped = image.cropping(to: rect) else { return image }
        return cropped
    }
    func reset() { selection = nil; start = nil; needsDisplay = true }
    override func setFrameSize(_ newSize: NSSize) { reset(); super.setFrameSize(newSize) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.08, alpha: 1).setFill(); bounds.fill()
        NSImage(cgImage: image, size: .zero).draw(in: imageRect, from: .zero, operation: .sourceOver,
                                               fraction: 1, respectFlipped: true, hints: nil)
        if let selection {
            NSColor.systemTeal.withAlphaComponent(0.18).setFill(); selection.fill()
            NSColor.systemTeal.setStroke(); let path = NSBezierPath(rect: selection); path.lineWidth = 2; path.stroke()
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard imageRect.contains(point) else { return }
        start = point; selection = nil; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                           width: abs(point.x - start.x), height: abs(point.y - start.y)).intersection(imageRect)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { mouseDragged(with: event); start = nil }
}

@MainActor final class ImagePreview: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func cancelOperation(_ sender: Any?) { cancel?() }
    let canvas: CropCanvas
    var add: ((CGImage) -> Void)?
    var cancel: (() -> Void)?
    var retake: (() -> Void)?
    private let addButton = NSButton(title: "Add to Chat", target: nil, action: nil)
    private let notice = NSTextField(wrappingLabelWithString: "Drag to crop, or keep the full image. Adding may upload it to ChatGPT; send your message yourself.")
    init(image: CGImage) {
        canvas = CropCanvas(image: image)
        super.init(frame: .zero)
        wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
        let title = NSTextField(labelWithString: "Image preview · \(image.width) × \(image.height)")
        title.font = .boldSystemFont(ofSize: 16)
        let reset = NSButton(title: "Reset crop", target: self, action: #selector(resetCrop))
        let again = NSButton(title: "Retake", target: self, action: #selector(captureAgain))
        let discard = NSButton(title: "Cancel", target: self, action: #selector(discardImage))
        addButton.target = self; addButton.action = #selector(addImage); addButton.bezelStyle = .rounded
        addButton.setAccessibilityIdentifier("image-add")
        reset.setAccessibilityIdentifier("crop-reset"); discard.setAccessibilityIdentifier("image-cancel")
        notice.setAccessibilityIdentifier("image-notice")
        let controls = NSStackView(views: [reset, again, discard, addButton]); controls.spacing = 8
        notice.font = .systemFont(ofSize: 12); notice.maximumNumberOfLines = 3
        for view in [title, canvas, notice, controls] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 14), title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            canvas.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8), canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: trailingAnchor), canvas.bottomAnchor.constraint(equalTo: notice.topAnchor, constant: -8),
            notice.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), notice.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            notice.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -10),
            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16), controls.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func busy(_ value: Bool) { addButton.isEnabled = !value }
    func showMessage(_ text: String) { notice.stringValue = text }
    @objc private func resetCrop() { canvas.reset() }
    @objc private func captureAgain() { retake?() }
    @objc private func discardImage() { cancel?() }
    @objc private func addImage() { add?(canvas.croppedImage) }
}
