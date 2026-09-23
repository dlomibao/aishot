import CoreGraphics

/// Every annotation is expressed in image *pixel* coordinates with a bottom-left
/// origin, never in view points. The canvas converts on input; the renderer never
/// has to know what scale it is being displayed at.
public enum Annotation: Equatable, Sendable {
    case arrow(from: CGPoint, to: CGPoint)
    case box(CGRect)
    /// `box` sets the wrap width; text flows from its top edge and grows
    /// downward, so the height is a starting hint rather than a clip.
    case text(box: CGRect, string: String)
    case badge(center: CGPoint, number: Int)
    case redact(CGRect)
    case highlight(CGRect)
}

extension Annotation {
    /// A shape too small to see or point at anything — usually a click that
    /// was meant to select a tool rather than draw. `minimum` is in image
    /// pixels, so callers scale it from screen points.
    ///
    /// Rectangles are dropped only when *both* sides are tiny. A long, thin
    /// box is a deliberate underline, not a stray click.
    public func isDegenerate(minimum: CGFloat) -> Bool {
        switch self {
        case let .arrow(from, to):
            return hypot(to.x - from.x, to.y - from.y) < minimum
        case let .box(rect), let .redact(rect), let .highlight(rect):
            return rect.width < minimum && rect.height < minimum
        case let .text(_, string):
            return string.isEmpty
        case .badge:
            return false
        }
    }

    public func translated(by offset: CGVector) -> Annotation {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + offset.dx, y: p.y + offset.dy) }
        func move(_ r: CGRect) -> CGRect { r.offsetBy(dx: offset.dx, dy: offset.dy) }
        switch self {
        case let .arrow(from, to):     return .arrow(from: move(from), to: move(to))
        case let .box(rect):           return .box(move(rect))
        case let .text(box, string):   return .text(box: move(box), string: string)
        case let .badge(center, n):    return .badge(center: move(center), number: n)
        case let .redact(rect):        return .redact(move(rect))
        case let .highlight(rect):     return .highlight(move(rect))
        }
    }
}

public enum Tool: Int, CaseIterable, Sendable {
    case select = 0, arrow, box, text, badge, redact, crop, highlight

    public var label: String {
        switch self {
        case .select: return "Select"
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .text: return "Text"
        case .badge: return "Number"
        case .redact: return "Redact"
        case .crop: return "Crop"
        case .highlight: return "Highlight"
        }
    }

    /// Shown in the toolbar and tooltips. Digits stay where they were before
    /// Select and Highlight existed, so learned shortcuts keep working.
    public var shortcut: String {
        self == .select ? "V" : "\(rawValue)"
    }

    /// Left-to-right toolbar order: related shapes sit together, which is not
    /// the same as shortcut order.
    public static let toolbarOrder: [Tool] = [.select, .arrow, .box, .highlight, .text, .badge, .redact, .crop]

    public var isDragBased: Bool {
        switch self {
        case .arrow, .box, .redact, .text, .crop, .highlight: return true
        case .badge, .select: return false
        }
    }

    /// Holding Shift turns these rectangles into squares.
    public var constrainsToSquare: Bool {
        switch self {
        case .box, .redact, .crop, .highlight: return true
        default: return false
        }
    }
}

/// A shape carries the style it was drawn with, so changing the colour affects
/// what you draw next rather than restyling the whole image.
public struct StyledAnnotation: Equatable, Sendable {
    public var shape: Annotation
    public var style: Style

    public init(_ shape: Annotation, style: Style) {
        self.shape = shape
        self.style = style
    }
}

/// Everything that undo and redo restore. Small enough that keeping whole
/// copies is simpler than recording each kind of edit, and it makes moving and
/// deleting undoable without special cases.
public struct DocumentState: Equatable, Sendable {
    public var annotations: [StyledAnnotation] = []
    /// Absolute, in the original image's pixel coordinates.
    public var crop: CGRect?

    public init() {}
}

public struct AnnotationDocument: Sendable {
    public private(set) var state = DocumentState()
    private var undoStack: [DocumentState] = []
    private var redoStack: [DocumentState] = []

    public init() {}

    public var annotations: [StyledAnnotation] { state.annotations }
    public var cropRect: CGRect? { state.crop }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// One past the highest badge on the canvas. Deleting a badge from the
    /// middle leaves a gap rather than renumbering the others, since you may
    /// already be referring to them by number.
    public var nextBadgeNumber: Int {
        let highest = state.annotations.compactMap { annotation -> Int? in
            if case let .badge(_, number) = annotation.shape { return number }
            return nil
        }.max() ?? 0
        return highest + 1
    }

    public mutating func add(_ shape: Annotation, style: Style) {
        commit { $0.annotations.append(StyledAnnotation(shape, style: style)) }
    }

    public mutating func crop(to rect: CGRect) {
        commit { $0.crop = rect }
    }

    public mutating func move(at index: Int, by offset: CGVector) {
        guard state.annotations.indices.contains(index), offset != .zero else { return }
        commit { $0.annotations[index].shape = $0.annotations[index].shape.translated(by: offset) }
    }

    public mutating func remove(at index: Int) {
        guard state.annotations.indices.contains(index) else { return }
        commit { $0.annotations.remove(at: index) }
    }

    /// Returns whether the crop changed, so the window knows to resize.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(state)
        return replaceState(with: previous)
    }

    /// Returns whether the crop changed, so the window knows to resize.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(state)
        return replaceState(with: next)
    }

    private mutating func commit(_ change: (inout DocumentState) -> Void) {
        var next = state
        change(&next)
        guard next != state else { return }
        undoStack.append(state)
        redoStack.removeAll()
        state = next
    }

    private mutating func replaceState(with target: DocumentState) -> Bool {
        let cropChanged = target.crop != state.crop
        state = target
        return cropChanged
    }
}
