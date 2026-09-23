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

    /// Index into `document.annotations`. Cleared by anything that can
    /// reorder or remove shapes, so it never points at the wrong one.
    private var selectedIndex: Int?
    /// True while dragging a selected shape; the document only changes on
    /// mouse-up, so the whole drag is one undo step.
    private var isMovingSelection = false
    private var shiftHeld = false

    /// A crop waits for confirmation rather than applying on mouse-up.
    private var pendingCrop: CGRect?
    private var cropConfirm: NSButton?
    private var cropCancel: NSButton?

    var tool: Tool = .arrow {
        didSet {
            commitPendingText()
            if oldValue == .crop { clearPendingCrop() }
            if tool != .select { clearSelection() }
            window?.invalidateCursorRects(for: self)
        }
    }

    var color: MarkupColor = .red { didSet { commitPendingText() } }
    var sizeClass: SizeClass = .medium { didSet { commitPendingText() } }

    var canUndo: Bool { document.canUndo }
    var canRedo: Bool { document.canRedo }
    var hasSelection: Bool { selectedIndex != nil }
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
        // Views stopped clipping by default in macOS 14. The canvas draws the
        // whole screenshot shifted by the crop, so without this a small crop
        // shows the uncropped image in the window space beside it.
        if #available(macOS 14.0, *) { clipsToBounds = true }
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
        // AppKit can pass a dirty rect larger than the view; never paint past
        // the canvas edge whatever the clipping setting.
        ctx.clip(to: bounds)
        ctx.interpolationQuality = .high

        ctx.saveGState()
        let f = 1 / transform.scale
        ctx.scaleBy(x: f, y: f)
        ctx.translateBy(x: -croppedBounds.minX, y: -croppedBounds.minY)
        ctx.draw(baseImage, in: CGRect(origin: .zero, size: imagePixelSize))
        let pending = pendingAnnotation.map { [StyledAnnotation($0, style: style)] } ?? []
        Renderer.draw(displayedAnnotations + pending, in: ctx)
        ctx.restoreGState()

        drawSelectionOutline(in: ctx)
        drawCropOverlay(in: ctx)
    }

    /// The document's shapes, with the one being dragged shown at its
    /// in-progress position.
    private var displayedAnnotations: [StyledAnnotation] {
        var shapes = document.annotations
        if let index = selectedIndex, let offset = moveOffset, shapes.indices.contains(index) {
            shapes[index].shape = shapes[index].shape.translated(by: offset)
        }
        return shapes
    }

    private var moveOffset: CGVector? {
        guard isMovingSelection, let start = dragStart, let current = dragCurrent else { return nil }
        let a = imagePoint(fromView: start), b = imagePoint(fromView: current)
        return CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }

    private func drawSelectionOutline(in ctx: CGContext) {
        let shapes = displayedAnnotations
        guard let index = selectedIndex, shapes.indices.contains(index) else { return }
        let rect = viewRect(fromImage: shapes[index].bounds).insetBy(dx: -4, dy: -4)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [5, 3])
        ctx.stroke(rect)
        ctx.restoreGState()
    }

    /// Dim everything outside the proposed crop so the result is obvious before
    /// it is committed.
    private func drawCropOverlay(in ctx: CGContext) {
        let selection: CGRect?
        if let pendingCrop {
            selection = viewRect(fromImage: pendingCrop)
        } else if tool == .crop, let start = dragStart, let current = constrainedCurrent {
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

    /// The drag's end point after Shift is applied: 45° steps for arrows,
    /// squares for rectangles.
    private var constrainedCurrent: CGPoint? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        guard shiftHeld, !isMovingSelection else { return current }
        if tool == .arrow { return Constrain.snapTo45Degrees(from: start, to: current) }
        if tool.constrainsToSquare { return Constrain.square(from: start, to: current) }
        return current
    }

    private var pendingAnnotation: Annotation? {
        guard !isMovingSelection, let start = dragStart, let current = constrainedCurrent,
              tool.isDragBased, tool != .crop else { return nil }
        let a = imagePoint(fromView: start)
        let b = imagePoint(fromView: current)
        switch tool {
        case .arrow:     return .arrow(from: a, to: b)
        case .box:       return .box(normalizedRect(from: a, to: b))
        case .redact:    return .redact(normalizedRect(from: a, to: b))
        case .highlight: return .highlight(normalizedRect(from: a, to: b))
        default:         return nil
        }
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        commitPendingText()
        let point = convert(event.locationInWindow, from: nil)
        shiftHeld = event.modifierFlags.contains(.shift)
        if tool == .crop { clearPendingCrop() }

        // ⌘-click selects from any tool, so fixing one shape does not mean
        // switching tools and back.
        if tool == .select || event.modifierFlags.contains(.command) {
            beginSelection(at: point)
            return
        }
        clearSelection()

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
        shiftHeld = event.modifierFlags.contains(.shift)
        needsDisplay = true
    }

    /// Lets Shift take effect mid-drag without moving the mouse.
    override func flagsChanged(with event: NSEvent) {
        shiftHeld = event.modifierFlags.contains(.shift)
        if dragStart != nil { needsDisplay = true }
        super.flagsChanged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; dragCurrent = nil; isMovingSelection = false; needsDisplay = true }
        shiftHeld = event.modifierFlags.contains(.shift)
        if isMovingSelection {
            finishMove()
            return
        }
        guard let start = dragStart, let current = constrainedCurrent else { return }
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
            // A few screen points, converted to image pixels.
            guard let annotation = pendingAnnotation,
                  !annotation.isDegenerate(minimum: 4 * transform.scale) else { return }
            document.add(annotation, style: style)
            changed()
        }
    }

    // MARK: - Selection

    private func beginSelection(at point: CGPoint) {
        let hit = document.annotations.indexOfShape(at: imagePoint(fromView: point),
                                                    tolerance: 6 * transform.scale)
        selectedIndex = hit
        if hit != nil {
            isMovingSelection = true
            dragStart = point
            dragCurrent = point
        }
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }

    private func finishMove() {
        guard let index = selectedIndex, let offset = moveOffset else { return }
        document.move(at: index, by: offset)
        changed()
    }

    func deleteSelection() {
        guard let index = selectedIndex else { return }
        selectedIndex = nil
        document.remove(at: index)
        changed()
    }

    /// Returns true if there was a selection to clear, so esc can back out of
    /// a selection before it means anything bigger.
    @discardableResult
    func clearSelection() -> Bool {
        guard selectedIndex != nil else { return false }
        selectedIndex = nil
        needsDisplay = true
        delegate?.canvasDidChange(self)
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: tool == .select ? .arrow : .crosshair)
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
        confirm.setAccessibilityLabel("Crop to selection")
        let cancel = NSButton(title: "✕", target: self, action: #selector(cancelCropTapped))
        cancel.bezelStyle = .circular
        cancel.toolTip = "Discard this selection — esc"
        cancel.setAccessibilityLabel("Cancel crop")

        // Prefer just beneath the selection's right edge, but clamp into the
        // view: a narrow crop near an edge would otherwise put the buttons
        // off-canvas, leaving no way to confirm.
        let size: CGFloat = 30
        let pairWidth = size * 2 + 6
        let below = rect.minY - size - 6
        let y = min(max(below >= 0 ? below : rect.minY + 6, 4), max(4, bounds.height - size - 4))
        let preferredX = rect.maxX - pairWidth
        let x = min(max(preferredX, 4), max(4, bounds.width - pairWidth - 4))
        confirm.frame = NSRect(x: x, y: y, width: size, height: size)
        cancel.frame = NSRect(x: x + size + 6, y: y, width: size, height: size)

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
        // White or yellow text on the light backdrop is close to invisible.
        field.backgroundColor = color.isLight
            ? NSColor.black.withAlphaComponent(0.72)
            : NSColor.white.withAlphaComponent(0.88)
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

    /// ⏎ commits. A newline needs a modifier, and which one people reach for
    /// depends on where they came from: ⌥⏎ and ⌃⏎ are the macOS standard
    /// bindings, ⇧⏎ has no system binding but is what chat apps trained
    /// everyone to expect. All three insert a line break.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewline(nil)
                return true
            }
            commitPendingText()
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)),
             #selector(NSResponder.insertLineBreak(_:)):
            textView.insertNewline(nil)
            return true
        default:
            return false
        }
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

    // MARK: - Commands

    /// Anything that would be lost by closing: committed operations, or text
    /// still being typed.
    var hasMarkup: Bool {
        canUndo || !(textEditor?.stringValue.isEmpty ?? true)
    }

    func discardPendingText() {
        textEditor?.removeFromSuperview()
        textEditor = nil
        textEditorBox = nil
        window?.makeFirstResponder(self)
    }

    func undo() {
        // While typing, ⌘Z belongs to the text, as in any other text field.
        if let editor = textEditor?.currentEditor() {
            editor.undoManager?.undo()
            return
        }
        if pendingCrop != nil {
            clearPendingCrop()
            return
        }
        applyHistoryStep(document.undo())
    }

    func redo() {
        if let editor = textEditor?.currentEditor() {
            editor.undoManager?.redo()
            return
        }
        guard pendingCrop == nil else { return }
        applyHistoryStep(document.redo())
    }

    /// A history step can remove or reorder shapes, so a remembered selection
    /// index could point at the wrong one afterwards.
    private func applyHistoryStep(_ cropChanged: Bool) {
        selectedIndex = nil
        if cropChanged { delegate?.canvasDidChangeBounds(self) }
        changed()
    }

    func exportPNG(size: ExportSize = .original) -> Data? {
        commitPendingText()
        clearPendingCrop()
        return Renderer.pngData(base: baseImage, annotations: document.annotations,
                                crop: document.cropRect, size: size)
    }

    private func changed() {
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }
}
