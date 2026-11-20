import AppKit
import CaptureCore

@MainActor final class CropCanvas: NSView {
    let image: CGImage
    private var start: CGPoint?
    // Image pixels, independent of the preview's current layout/Retina scale.
    private var selectedPixels: CGRect?
    var isDragging: Bool { start != nil }
    private var selection: CGRect? {
        selectedPixels.map { rect in
            CGRect(x: imageRect.minX + rect.minX / CGFloat(image.width) * imageRect.width,
                   y: imageRect.minY + rect.minY / CGFloat(image.height) * imageRect.height,
                   width: rect.width / CGFloat(image.width) * imageRect.width,
                   height: rect.height / CGFloat(image.height) * imageRect.height)
        }
    }
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
        guard let rect = selectedPixels?.integral,
              let cropped = image.cropping(to: rect) else { return image }
        return cropped
    }
    func reset() { selectedPixels = nil; start = nil; needsDisplay = true }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsDisplay = true }
    private func pixels(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - imageRect.minX) / imageRect.width * CGFloat(image.width),
                y: (point.y - imageRect.minY) / imageRect.height * CGFloat(image.height))
    }
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
        start = pixels(point); selectedPixels = nil; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = pixels(convert(event.locationInWindow, from: nil))
        let rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                          width: abs(point.x - start.x), height: abs(point.y - start.y))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        selectedPixels = rect.isEmpty || rect.isNull ? nil : rect
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
    private let addButton = NSButton(title: "Add to Chat ↵", target: nil, action: nil)
    var canConfirm: Bool { addButton.isEnabled && !canvas.isDragging }
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
        addButton.setAccessibilityLabel("Add to Chat")
        addButton.toolTip = "Return or keypad Enter adds this image. It never sends the message."
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
    @objc func addImage() {
        guard canConfirm else { return }
        busy(true) // Close the click/key race before starting asynchronous encoding.
        add?(canvas.croppedImage)
    }
}
