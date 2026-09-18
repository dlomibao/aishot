import CoreGraphics

/// Every annotation is expressed in image *pixel* coordinates with a bottom-left
/// origin, never in view points. The canvas converts on input; the renderer never
/// has to know what scale it is being displayed at.
public enum Annotation: Equatable, Sendable {
    case arrow(from: CGPoint, to: CGPoint)
    case box(CGRect)
    case text(origin: CGPoint, string: String)
    case badge(center: CGPoint, number: Int)
    case redact(CGRect)
}

public enum Tool: Int, CaseIterable, Sendable {
    case arrow = 1, box, text, badge, redact

    public var label: String {
        switch self {
        case .arrow: return "Arrow"
        case .box: return "Box"
        case .text: return "Text"
        case .badge: return "Number"
        case .redact: return "Redact"
        }
    }

    public var isDragBased: Bool {
        switch self {
        case .arrow, .box, .redact: return true
        case .text, .badge: return false
        }
    }
}

public struct AnnotationDocument: Sendable {
    public private(set) var annotations: [Annotation] = []

    public init() {}

    /// Badges number themselves by how many are currently placed, so undoing one
    /// frees its number again rather than leaving a gap.
    public var nextBadgeNumber: Int {
        annotations.reduce(1) { count, annotation in
            if case .badge = annotation { return count + 1 }
            return count
        }
    }

    public mutating func add(_ annotation: Annotation) {
        annotations.append(annotation)
    }

    public mutating func undo() {
        _ = annotations.popLast()
    }

    public var isEmpty: Bool { annotations.isEmpty }
}
