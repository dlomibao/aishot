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
}

public enum Tool: Int, CaseIterable, Sendable {
    case arrow = 1, box, text, badge, redact, crop

    public var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .text: return "Text"
        case .badge: return "Number"
        case .redact: return "Redact"
        case .crop: return "Crop"
        }
    }

    public var isDragBased: Bool {
        switch self {
        case .arrow, .box, .redact, .text, .crop: return true
        case .badge: return false
        }
    }
}

/// A shape carries the style it was drawn with, so changing the colour affects
/// what you draw next rather than restyling the whole image.
public struct StyledAnnotation: Sendable {
    public var shape: Annotation
    public var style: Style

    public init(_ shape: Annotation, style: Style) {
        self.shape = shape
        self.style = style
    }
}

/// One entry in the undo stack. Cropping sits alongside drawing so that ⌘Z
/// walks back through both, and a mis-crop never destroys markup.
public enum Operation: Sendable {
    case annotation(StyledAnnotation)
    /// Absolute, in the original image's pixel coordinates.
    case crop(CGRect)
}

public struct AnnotationDocument: Sendable {
    public private(set) var operations: [Operation] = []

    public init() {}

    public var annotations: [StyledAnnotation] {
        operations.compactMap { if case let .annotation(a) = $0 { return a } else { return nil } }
    }

    /// Crops are stored absolute, so the one in effect is simply the last one.
    public var cropRect: CGRect? {
        for operation in operations.reversed() {
            if case let .crop(rect) = operation { return rect }
        }
        return nil
    }

    public mutating func crop(to rect: CGRect) {
        operations.append(.crop(rect))
    }

    /// Badges number themselves by how many are currently placed, so undoing one
    /// frees its number again rather than leaving a gap.
    public var nextBadgeNumber: Int {
        annotations.reduce(1) { count, annotation in
            if case .badge = annotation.shape { return count + 1 }
            return count
        }
    }

    public mutating func add(_ shape: Annotation, style: Style) {
        operations.append(.annotation(StyledAnnotation(shape, style: style)))
    }

    public mutating func undo() {
        _ = operations.popLast()
    }

    public var isEmpty: Bool { operations.isEmpty }

    /// True when undoing would change the visible bounds, so the window knows
    /// it has to resize.
    public var lastOperationIsCrop: Bool {
        if case .crop = operations.last { return true }
        return false
    }
}
