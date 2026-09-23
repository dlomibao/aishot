import CoreGraphics

extension StyledAnnotation {
    /// The area the shape visibly covers, in image pixels. Used for the
    /// selection outline and for hit-testing filled shapes.
    public var bounds: CGRect {
        switch shape {
        case let .arrow(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y))
                .insetBy(dx: -style.lineWidth * 2, dy: -style.lineWidth * 2)
        case let .box(rect):
            return rect
        case let .text(box, string):
            // Text flows down from the top edge and can outgrow the box it
            // was typed into, so measure what actually renders.
            let height = max(box.height, Renderer.textHeight(string, width: box.width, style: style))
            return CGRect(x: box.minX, y: box.maxY - height, width: box.width, height: height)
        case let .badge(center, _):
            let r = style.badgeRadius
            return CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        case let .redact(rect), let .highlight(rect):
            return rect
        }
    }

    /// Outlined shapes (arrows, boxes) are hit on their stroke, so a big box
    /// drawn around something does not swallow clicks meant for what is
    /// inside it. Filled shapes are hit anywhere inside.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let reach = tolerance + style.lineWidth / 2
        switch shape {
        case let .arrow(from, to):
            return distance(from: point, toSegment: from, to) <= reach
        case let .box(rect):
            let outer = rect.insetBy(dx: -reach, dy: -reach)
            let inner = rect.insetBy(dx: reach, dy: reach)
            return outer.contains(point) && (inner.isEmpty || !inner.contains(point))
        case .badge, .text, .redact, .highlight:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }
}

extension Array where Element == StyledAnnotation {
    /// The topmost shape under the point, since later shapes draw on top.
    public func indexOfShape(at point: CGPoint, tolerance: CGFloat) -> Int? {
        indices.reversed().first { self[$0].hitTest(point, tolerance: tolerance) }
    }
}

func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}
