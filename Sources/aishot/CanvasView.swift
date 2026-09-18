import AIShotCore
import AppKit

@MainActor
protocol CanvasViewDelegate: AnyObject {
    func canvasDidChange(_ view: CanvasView)
}

/// Draws the screenshot and the committed annotations, plus the shape currently
/// being dragged. Not flipped: the view shares the image's bottom-left origin so
/// the transform is a pure scale.
@MainActor
final class CanvasView: NSView {
    weak var delegate: CanvasViewDelegate?

    private let baseImage: CGImage
    private let style: Style
    private var document = AnnotationDocument()
    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?
    private var textEditor: NSTextField?

    var tool: Tool = .arrow {
        didSet { commitPendingText() }
    }

    var canUndo: Bool { !document.isEmpty }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    private var transform: CanvasTransform {
        CanvasTransform(imageSize: CGSize(width: baseImage.width, height: baseImage.height),
                        viewSize: bounds.size)
    }

    init(image: CGImage, frame: NSRect) {
        self.baseImage = image
        self.style = .scaled(to: CGSize(width: image.width, height: image.height))
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(baseImage, in: bounds)

        // Scale the pixel-space annotations down into view space, so what is on
        // screen is exactly what the exporter will produce.
        ctx.saveGState()
        let factor = 1 / transform.scale
        ctx.scaleBy(x: factor, y: factor)
        Renderer.draw(document.annotations + pendingAnnotation.map { [$0] }.orEmpty, in: ctx, style: style)
        ctx.restoreGState()
    }

    private var pendingAnnotation: Annotation? {
        guard let start = dragStart, let current = dragCurrent, tool.isDragBased else { return nil }
        let a = transform.imagePoint(fromView: start)
        let b = transform.imagePoint(fromView: current)
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
        switch tool {
        case .text:
            beginTextEntry(at: point)
        case .badge:
            document.add(.badge(center: transform.imagePoint(fromView: point), number: document.nextBadgeNumber))
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
        defer { dragStart = nil; dragCurrent = nil }
        guard let annotation = pendingAnnotation else { return }
        // Ignore stray clicks that produced a degenerate shape.
        if case let .box(rect) = annotation, rect.width < 2, rect.height < 2 { return }
        if case let .redact(rect) = annotation, rect.width < 2, rect.height < 2 { return }
        document.add(annotation)
        changed()
    }

    // MARK: - Text entry

    private func beginTextEntry(at point: CGPoint) {
        let viewFontSize = style.fontSize / transform.scale
        let height = (viewFontSize * 1.8).rounded()
        let field = NSTextField(frame: NSRect(x: point.x, y: point.y - height * 0.3,
                                              width: max(160, bounds.width - point.x - 8),
                                              height: height))
        field.font = NSFont(name: style.fontName, size: viewFontSize) ?? .boldSystemFont(ofSize: viewFontSize)
        field.textColor = NSColor(cgColor: style.color)
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "type, then ⏎"
        field.target = self
        field.action = #selector(textFieldCommitted)
        addSubview(field)
        window?.makeFirstResponder(field)
        textEditor = field
    }

    @objc private func textFieldCommitted() {
        commitPendingText()
    }

    /// CoreText draws from a baseline, so take the field's actual first baseline
    /// rather than guessing an offset — otherwise the text jumps on commit.
    func commitPendingText() {
        guard let field = textEditor else { return }
        let string = field.stringValue
        let textRect = field.cell?.titleRect(forBounds: field.bounds) ?? field.bounds
        let baselineFromTop = field.firstBaselineOffsetFromTop
        let origin = CGPoint(x: field.frame.minX + textRect.minX,
                             y: field.frame.maxY - baselineFromTop)
        textEditor = nil
        field.removeFromSuperview()
        window?.makeFirstResponder(self)
        guard !string.isEmpty else { return }
        document.add(.text(origin: transform.imagePoint(fromView: origin), string: string))
        changed()
    }

    var isEditingText: Bool { textEditor != nil }

    // MARK: - Commands

    func undo() {
        if textEditor != nil {
            textEditor?.removeFromSuperview()
            textEditor = nil
            window?.makeFirstResponder(self)
            return
        }
        document.undo()
        changed()
    }

    func exportPNG() -> Data? {
        commitPendingText()
        return Renderer.pngData(base: baseImage, annotations: document.annotations, style: style)
    }

    private func changed() {
        needsDisplay = true
        delegate?.canvasDidChange(self)
    }
}

private extension Optional where Wrapped == [Annotation] {
    var orEmpty: [Annotation] { self ?? [] }
}
