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
            case let .text(box, string):   drawText(string, in: box, ctx: ctx, style: style)
            case let .badge(center, n):    drawBadge(n, at: center, in: ctx, style: style)
            case let .redact(rect):        drawRedaction(rect, in: ctx)
            }
            ctx.restoreGState()
        }
    }

    public static func render(base: CGImage, annotations: [StyledAnnotation]) -> CGImage? {
        render(base: base, annotations: annotations, crop: nil)
    }

    /// Everything is expressed in the *original* image's coordinates. Cropping
    /// shifts the context rather than rewriting the annotations, so a crop can
    /// be undone without having to move anything back.
    public static func render(base: CGImage, annotations: [StyledAnnotation], crop: CGRect?) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let visible = (crop.map { $0.intersection(full) }?.isEmpty == false ? crop!.intersection(full) : full)
            .integral

        guard visible.width >= 1, visible.height >= 1,
              let ctx = CGContext(data: nil, width: Int(visible.width), height: Int(visible.height),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: -visible.minX, y: -visible.minY)
        ctx.draw(base, in: full)
        draw(annotations, in: ctx)
        return ctx.makeImage()
    }

    /// The visible bounds after a crop, clamped to the image.
    public static func visibleRect(imageSize: CGSize, crop: CGRect?) -> CGRect {
        let full = CGRect(origin: .zero, size: imageSize)
        guard let crop else { return full }
        let clamped = crop.intersection(full).integral
        return clamped.width >= 1 && clamped.height >= 1 ? clamped : full
    }

    public static func pngData(base: CGImage, annotations: [StyledAnnotation], crop: CGRect? = nil) -> Data? {
        guard let image = render(base: base, annotations: annotations, crop: crop) else { return nil }
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

    /// Wraps within the box's width, flowing down from its top edge. The box
    /// height is where typing started, not a clip — long text grows past it
    /// rather than disappearing.
    private static func drawText(_ string: String, in box: CGRect, ctx: CGContext, style: Style) {
        guard !string.isEmpty, box.width >= 1 else { return }
        let attributed = attributed(string, style: style)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let height = textHeight(framesetter: framesetter, width: box.width)
        let flowed = CGRect(x: box.minX, y: box.maxY - height, width: box.width, height: height)
        ctx.textMatrix = .identity
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0),
                                             CGPath(rect: flowed, transform: nil), nil)
        CTFrameDraw(frame, ctx)
    }

    private static func textHeight(framesetter: CTFramesetter, width: CGFloat) -> CGFloat {
        var fitRange = CFRange()
        let size = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRangeMake(0, 0), nil,
            CGSize(width: width, height: .greatestFiniteMagnitude), &fitRange)
        return ceil(size.height)
    }

    /// How tall the text will render at a given width — used by the editor to
    /// grow the input box as you type.
    public static func textHeight(_ string: String, width: CGFloat, style: Style) -> CGFloat {
        guard !string.isEmpty, width >= 1 else { return style.fontSize * 1.3 }
        return textHeight(framesetter: CTFramesetterCreateWithAttributedString(attributed(string, style: style)),
                          width: width)
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
        // Word wrapping, set explicitly rather than relying on the default.
        // CoreText still breaks a token too long to fit on its own line.
        var breakMode = CTLineBreakMode.byWordWrapping
        let paragraph = withUnsafeBytes(of: &breakMode) { raw -> CTParagraphStyle in
            var setting = CTParagraphStyleSetting(spec: .lineBreakMode,
                                                  valueSize: MemoryLayout<CTLineBreakMode>.size,
                                                  value: raw.baseAddress!)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: style.color,
            kCTParagraphStyleAttributeName: paragraph,
        ]
        return CFAttributedStringCreate(nil, string as CFString, attributes as CFDictionary)
    }

}
