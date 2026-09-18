import CoreGraphics

/// Stroke and type sizes are derived from the image's pixel dimensions so a 4K
/// screenshot and a 300px crop get visually comparable markup.
public struct Style: Sendable {
    public var color: CGColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    public var fontName: String

    public var badgeRadius: CGFloat { fontSize * 0.95 }

    public init(color: CGColor, lineWidth: CGFloat, fontSize: CGFloat, fontName: String = "Helvetica-Bold") {
        self.color = color
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.fontName = fontName
    }

    public static let markupRed = CGColor(red: 0.91, green: 0.15, blue: 0.13, alpha: 1)

    public static func scaled(to imageSize: CGSize) -> Style {
        let shortEdge = min(imageSize.width, imageSize.height)
        return Style(color: markupRed,
                     lineWidth: max(2, (shortEdge * 0.006).rounded()),
                     fontSize: max(12, (shortEdge * 0.030).rounded()))
    }
}
