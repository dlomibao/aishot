import CoreGraphics

/// Maps between the view's points and the image's pixels. Both spaces use a
/// bottom-left origin, so this is a uniform scale with no axis flip.
public struct CanvasTransform: Sendable {
    public let imageSize: CGSize
    public let viewSize: CGSize

    public init(imageSize: CGSize, viewSize: CGSize) {
        self.imageSize = imageSize
        self.viewSize = viewSize
    }

    public var scale: CGFloat {
        guard viewSize.width > 0 else { return 1 }
        return imageSize.width / viewSize.width
    }

    public func imagePoint(fromView point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale, y: point.y * scale)
    }

    public func viewPoint(fromImage point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scale, y: point.y / scale)
    }

    public func imageRect(fromView rect: CGRect) -> CGRect {
        CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale,
               width: rect.width * scale, height: rect.height * scale)
    }

    /// Aspect-fit, and never upscale — a small screenshot stays crisp at 1:1.
    public static func fittedViewSize(imageSize: CGSize, maxSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return maxSize }
        let factor = min(maxSize.width / imageSize.width, maxSize.height / imageSize.height, 1)
        return CGSize(width: (imageSize.width * factor).rounded(),
                      height: (imageSize.height * factor).rounded())
    }
}

public func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
}
