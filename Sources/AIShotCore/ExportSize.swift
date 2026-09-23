import CoreGraphics
import Foundation

/// How big the copied image is allowed to be. Vision models bill by pixel area,
/// so a full Retina grab costs several times what the model needs to read it.
public enum ExportSize: String, CaseIterable, Sendable {
    case original
    case long2576
    case long1568
    case long1280

    /// Current Claude models take up to 2576px on the long edge without
    /// scaling; 1568px was the limit before that and is still readable for
    /// code; 1280 is the cheapest setting that keeps UI text legible.
    public var maxLongEdge: CGFloat? {
        switch self {
        case .original: return nil
        case .long2576: return 2576
        case .long1568: return 1568
        case .long1280: return 1280
        }
    }

    public var label: String {
        switch self {
        case .original: return "Original"
        case .long2576: return "2576px"
        case .long1568: return "1568px"
        case .long1280: return "1280px"
        }
    }

    public static let defaultForCopy: ExportSize = .long1568

    /// Never enlarges: a small crop keeps its own pixels.
    public func fittedSize(for size: CGSize) -> CGSize {
        guard let limit = maxLongEdge else { return size }
        let longEdge = max(size.width, size.height)
        guard longEdge > limit, longEdge > 0 else { return size }
        let factor = limit / longEdge
        return CGSize(width: max(1, (size.width * factor).rounded()),
                      height: max(1, (size.height * factor).rounded()))
    }
}

extension Renderer {
    public static func resized(_ image: CGImage, to exportSize: ExportSize) -> CGImage? {
        let target = exportSize.fittedSize(for: CGSize(width: image.width, height: image.height))
        guard Int(target.width) != image.width || Int(target.height) != image.height else { return image }
        guard let ctx = CGContext(data: nil, width: Int(target.width), height: Int(target.height),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(origin: .zero, size: target))
        return ctx.makeImage()
    }

    /// Markup is drawn at full resolution first and the result scaled down,
    /// so thin strokes and text are resampled together with the screenshot
    /// instead of being drawn at a size they were never styled for.
    public static func pngData(base: CGImage, annotations: [StyledAnnotation], crop: CGRect?,
                               size exportSize: ExportSize) -> Data? {
        guard let full = render(base: base, annotations: annotations, crop: crop),
              let sized = resized(full, to: exportSize) else { return nil }
        return pngData(of: sized)
    }
}
