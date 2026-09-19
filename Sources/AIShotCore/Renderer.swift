import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The single source of truth for what an annotation looks like. The on-screen
/// canvas and the exported PNG both call `draw`, which is what makes the editor
/// WYSIWYG: the preview is this same code running at a different scale.
public enum Renderer {

    public static func draw(_ annotations: [StyledAnnotation], in ctx: CGContext) {
        for annotation in annotations {
            let style = annotation.style
            ctx.saveGState()
            switch annotation.shape {
            case let .arrow(from, to):     drawArrow(from: from, to: to, in: ctx, style: style)
            case let .box(rect):           drawBox(rect, in: ctx, style: style)
            case let .text(origin, string): drawText(string, at: origin, in: ctx, style: style)
            case let .badge(center, n):    drawBadge(n, at: center, in: ctx, style: style)
            case let .redact(rect):        drawRedaction(rect, in: ctx)
            }
            ctx.restoreGState()
        }
    }

    public static func render(base: CGImage, annotations: [StyledAnnotation]) -> CGImage? {
        let width = base.width, height = base.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        draw(annotations, in: ctx)
        return ctx.makeImage()
    }

    public static func pngData(base: CGImage, annotations: [StyledAnnotation]) -> Data? {
        guard let image = render(base: base, annotations: annotations) else { return nil }
        return pngData(of: image)
    }

    public static func pngData(of image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    // MARK: - Shapes

    private static func drawBox(_ rect: CGRect, in ctx: CGContext, style: Style) {
        ctx.setStrokeColor(style.color)
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineJoin(.round)
        ctx.stroke(rect.insetBy(dx: style.lineWidth / 2, dy: style.lineWidth / 2))
    }

    private static func drawRedaction(_ rect: CGRect, in ctx: CGContext) {
        // .copy so the pixels are replaced outright — a redaction that merely
        // composited would still leak the original through any alpha.
        ctx.setBlendMode(.copy)
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(rect)
    }

    private static func drawArrow(from: CGPoint, to: CGPoint, in ctx: CGContext, style: Style) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.5 else { return }

        let headLength = min(max(style.lineWidth * 4.5, 10), length)
        let headWidth = headLength * 0.85
        let ux = dx / length, uy = dy / length
        let neck = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        let px = -uy, py = ux

        ctx.setStrokeColor(style.color)
        ctx.setFillColor(style.color)
        ctx.setLineWidth(style.lineWidth)
        ctx.setLineCap(.round)

        // Stop the shaft at the neck so the line does not show through a
        // semi-transparent head or thicken the tip.
        ctx.move(to: from)
        ctx.addLine(to: neck)
        ctx.strokePath()

        ctx.move(to: to)
        ctx.addLine(to: CGPoint(x: neck.x + px * headWidth / 2, y: neck.y + py * headWidth / 2))
        ctx.addLine(to: CGPoint(x: neck.x - px * headWidth / 2, y: neck.y - py * headWidth / 2))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawText(_ string: String, at origin: CGPoint, in ctx: CGContext, style: Style) {
        guard !string.isEmpty else { return }
        let line = CTLineCreateWithAttributedString(attributed(string, style: style))
        ctx.textMatrix = .identity
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
    }

    private static func drawBadge(_ number: Int, at center: CGPoint, in ctx: CGContext, style: Style) {
        let r = style.badgeRadius
        ctx.setFillColor(style.color)
        ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

        var white = style
        white.color = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        white.fontSize = style.fontSize * 0.95
        let line = CTLineCreateWithAttributedString(attributed("\(number)", style: white))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: center.x - bounds.width / 2 - bounds.minX,
                                   y: center.y - bounds.height / 2 - bounds.minY)
        CTLineDraw(line, ctx)
    }

    private static func attributed(_ string: String, style: Style) -> CFAttributedString {
        let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: style.color,
        ]
        return CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)
    }

    /// Text is drawn from a baseline; the editor places it from where you clicked.
    public static func textSize(_ string: String, style: Style) -> CGSize {
        guard !string.isEmpty else { return .zero }
        let line = CTLineCreateWithAttributedString(attributed(string, style: style))
        let bounds = CTLineGetBoundsWithOptions(line, [])
        return CGSize(width: bounds.width, height: bounds.height)
    }
}
