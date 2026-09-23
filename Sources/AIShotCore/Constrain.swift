import CoreGraphics

/// What holding Shift does while dragging.
public enum Constrain {
    /// Snaps the end point to the nearest 45° direction from the start,
    /// keeping the dragged length.
    public static func snapTo45Degrees(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0 else { return end }
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// Makes the dragged rectangle square, using the longer side and keeping
    /// the drag direction, so the corner still follows the pointer.
    public static func square(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let side = max(abs(dx), abs(dy))
        return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
    }
}
