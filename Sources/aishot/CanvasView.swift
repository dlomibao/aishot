import AIShotCore
import AppKit

@MainActor
protocol CanvasViewDelegate: AnyObject {
    func canvasDidChange(_ view: CanvasView)
    /// The visible bounds changed (a crop was applied or undone), so the window
    /// needs to resize around the new image.
    func canvasDidChangeBounds(_ view: CanvasView)
}

/// Draws the screenshot and its annotations, plus whatever is being dragged.
/// Not flipped: the view shares the image's bottom-left origin, so view↔image
/// is a scale and an offset with no axis flip.
@MainActor
final class CanvasView: NSView, NSTextFieldDelegate {
    weak var delegate: CanvasViewDelegate?

    private let baseImage: CGImage
    private var document = AnnotationDocument()
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var textEditor: NSTextField?
    private var textEditorBox: CGRect?

    /// A crop waits for confirmation rather than applying on mouse-up.
    private var pendingCrop: CGRect?
    private var cropConfirm: NSButton?
    private var cropCancel: NSButton?

    var tool: Tool = .arrow {
        didSet {
            commitPendingText()
            if oldValue == .crop { clearPendingCrop() }
        }
    }

    var color: MarkupColor = .red { didSet { commitPendingText() } }
    var sizeClass: SizeClass = .medium { didSet { commitPendingText() } }

    var canUndo: Bool { !document.isEmpty }
    var hasPendingCrop: Bool { pendingCrop != nil }
    var isEditingText: Bool { textEditor != nil }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private var imagePixelSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    /// The part of the original image currently on screen.
    var croppedBounds: CGRect {
        Renderer.visibleRect(imageSize: imagePixelSize, crop: document.cropRect)
    }

    private var transform: CanvasTransform {
        CanvasTransform(imageSize: croppedBounds.size, viewSize: bounds.size)
    }

    private var style: Style {
        .scaled(to: croppedBounds.size,
                backingScale: window?.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2,
                color: color, size: sizeClass)
    }

    init(image: CGImage, frame: NSRect) {
        self.baseImage = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Coordinates

    /// Annotations live in the *original* image's coordinates, so a crop can be
    /// undone without moving anything back.
    private func imagePoint(fromView point: CGPoint) -> CGPoint {
        let local = transform.imagePoint(fromView: point)
        return CGPoint(x: croppedBounds.minX + local.x, y: croppedBounds.minY + local.y)
    }

    private func imageRect(fromView rect: CGRect) -> CGRect {
        let local = transform.imageRect(fromView: rect)
        return local.offsetBy(dx: croppedBounds.minX, dy: croppedBounds.minY)
    }

    private func viewRect(fromImage rect: CGRect) -> CGRect {
        let local = rect.offsetBy(dx: -croppedBounds.minX, dy: -croppedBounds.minY)
        let f = 1 / transform.scale
        return CGRect(x: local.minX * f, y: local.minY * f, width: local.width * f, height: local.height * f)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high

        ctx.saveGState()
        let f = 1 / transform.scale
        ctx.scaleBy(x: f, y: f)
        ctx.translateBy(x: -croppedBounds.minX, y: -croppedBounds.minY)
        ctx.draw(baseImage, in: CGRect(origin: .zero, size: imagePixelSize))
        let pending = pendingAnnotation.map { [StyledAnnotation($0, style: style)] } ?? []
        Renderer.draw(document.annotations + pending, in: ctx)
        ctx.restoreGState()

        drawCropOverlay(in: ctx)
    }

    /// Dim everything outside the proposed crop so the result is obvious before
    /// it is committed.
    private func drawCropOverlay(in ctx: CGContext) {
        let selection: CGRect?
        if let pendingCrop {
            selection = viewRect(fromImage: pendingCrop)
        } else if tool == .crop, let start = dragStart, let current = dragCurrent {
            selection = normalizedRect(from: start, to: current)
        } else {
            selection = nil
        }
        guard let rect = selection else { return }

        ctx.saveGState()
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
        ctx.addRect(bounds)
        ctx.addRect(rect)
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        ctx.restoreGState()
    }

    private var pendingAnnotation: Annotation? {
        guard let start = dragStart, let current = dragCurrent, tool.isDragBased, tool != .crop else { return nil }
        let a = imagePoint(fromView: start)
        let b = imagePoint(fromView: current)
        switch tool {
        case .arrow:  return .arrow(from: a, to: b)
        case .box:    return .box(normalizedRect(from: a, to: b))
        case .redact: return .redact(normalizedRect(from: a, to: b))
        default:      return nil
        }
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        commitPendingText()
        let point = convert(event.locationInWindow, from: nil)
        if tool == .crop { clearPendingCrop() }

        switch tool {
        case .badge:
            document.add(.badge(center: imagePoint(fromView: point), number: document.nextBadgeNumber), style: style)
            changed()
        default:
            dragStart = point
            dragCurrent = point
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragCurrent = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragCurrent = nil; needsDisplay = true }
        guard let start = dragStart, let current = dragCurrent else { return }
        let dragged = normalizedRect(from: start, to: current)

        switch tool {
        case .crop:
            guard dragged.width >= 8, dragged.height >= 8 else { return }
            proposeCrop(imageRect(fromView: dragged))
        case .text:
            // A click rather than a drag still works; it just gets a default
            // wrap width instead of one you chose.
            let box = dragged.width >= 24 ? dragged
                : CGRect(x: start.x, y: start.y - style.fontSize / transform.scale * 1.4,
                         width: min(260, max(120, bounds.width - start.x - 8)),
                         height: style.fontSize / transform.scale * 1.4)
            beginTextEntry(in: box)
        default:
            guard let annotation = pendingAnnotation else { return }
            if case let .box(rect) = annotation, rect.width < 2, rect.height < 2 { return }
            if case let .redact(rect) = annotation, rect.width < 2, rect.height < 2 { return }
            document.add(annotation, style: style)
            changed()
        }
    }

    // MARK: - Crop

    private func proposeCrop(_ rect: CGRect) {
        pendingCrop = rect.intersection(croppedBounds).integral
        showCropButtons()
        needsDisplay = true
    }

    private func showCropButtons() {
        clearCropButtons()
        guard let pendingCrop else { return }
        let rect = viewRect(fromImage: pendingCrop)

        let confirm = NSButton(title: "✓", target: self, action: #selector(confirmCrop))
        confirm.bezelStyle = .circular
        confirm.toolTip = "Crop to this region — ⏎ or C"
        let cancel = NSButton(title: "✕", target: self, action: #selector(cancelCropTapped))
        cancel.bezelStyle = .circular
        cancel.toolTip = "Discard this selection — esc"

        // Sit inside the selection when there is no room beneath it.
        let size: CGFloat = 30
        let below = rect.minY - size - 6
        let y = below >= 0 ? below : rect.minY + 6
        confirm.frame = NSRect(x: min(rect.maxX - size * 2 - 10, bounds.width - size * 2 - 14), y: y, width: size, height: size)
        cancel.frame = NSRect(x: confirm.frame.maxX + 6, y: y, width: size, height: size)

        addSubview(confirm)
        addSubview(cancel)
        cropConfirm = confirm
        cropCancel = cancel
    }

    private func clearCropButtons() {
        cropConfirm?.removeFromSuperview()
        cropCancel?.removeFromSuperview()
        cropConfirm = nil
        cropCancel = nil
    }

    private func clearPendingCrop() {
        pendingCrop = nil
        clearCropButtons()
        needsDisplay = true
    }

    @objc func confirmCrop() {
        guard let pendingCrop, pendingCrop.width >= 1, pendingCrop.height >= 1 else { return }
        clearPendingCrop()
        document.crop(to: pendingCrop)
        delegate?.canvasDidChangeBounds(self)
        changed()
    }

    @objc private func cancelCropTapped() {
        clearPendingCrop()
    }

    /// Returns true if it consumed the key.
    func cancelPendingCrop() -> Bool {
        guard pendingCrop != nil else { return false }
        clearPendingCrop()
        return true
    }

    // MARK: - Text

    private func beginTextEntry(in box: CGRect) {
        let viewFontSize = style.fontSize / transform.scale
        let field = NSTextField(frame: box)
        field.font = NSFont(name: style.fontName, size: viewFontSize) ?? .boldSystemFont(ofSize: viewFontSize)
        field.textColor = NSColor(cgColor: style.color)
        field.backgroundColor = NSColor.white.withAlphaComponent(0.88)
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "type, then ⏎"
        field.usesSingleLineMode = false
        field.lineBreakMode = .byWordWrapping
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.delegate = self
        field.target = self
        field.action = #selector(textFieldCommitted)
        addSubview(field)
        window?.makeFirstResponder(field)
        textEditor = field
        textEditorBox = box
    }

    /// Grow the field downward as the text wraps, so what you type matches what
    /// gets rendered.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = textEditor, let box = textEditorBox else { return }
        let imageWidth = box.width * transform.scale
        let height = Renderer.textHeight(field.stringValue, width: imageWidth, style: style) / transform.scale
        let clamped = max(box.height, height + 4)
        field.frame = NSRect(x: box.minX, y: box.maxY - clamped, width: box.width, height: clamped)
    }

    @objc private func textFieldCommitted() {
        commitPendingText()
    }

    func commitPendingText() {
        guard let field = textEditor else { return }
        let string = field.stringValue
        let frame = field.frame
        textEditor = nil
        textEditorBox = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !string.isEmpty else { return }

        let inset = field.cell?.titleRect(forBounds: field.bounds) ?? field.bounds
        let boxInView = CGRect(x: frame.minX + inset.minX, y: frame.minY + inset.minY,
                               width: inset.width, height: inset.height)
        document.add(.text(box: imageRect(fromView: boxInView), string: string), style: style)
        changed()
    }

    func pasteIntoTextEditor() {
        textEditor?.currentEditor()?.paste(nil)
    }

    // MARK: - Commands

    func undo() {
        if textEditor != nil {
            textEditor?.removeFromSuperview()
            textEditor = nil
            textEditorBox = nil
            window?.makeFirstResponder(self)
            return
        }
        if pendingCrop != nil {
            clearPendingCrop()
            return
        }
        let boundsChange = document.lastOperationIsCrop
        document.undo()
        if boundsChange { delegate?.canvasDidChangeBounds(self) }
        changed()
    }

    func exportPNG() -> Data? {
        commitPendingText()
        clearPendingCrop()
        return Renderer.pngData(base: baseImage, annotations: document.annotations, crop: document.cropRect)
    }

    private func changed() {
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }
}
