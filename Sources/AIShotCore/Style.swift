import CoreGraphics

/// Stroke and type sizes derive from the image's pixel dimensions so a 4K
/// screenshot and a 300px crop get visually comparable markup. The size class
/// multiplies that base rather than setting fixed pixel counts, so "large"
/// means large relative to the image either way.
public enum SizeClass: String, CaseIterable, Sendable {
    case small, medium, large

    public var label: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        }
    }

    public var multiplier: CGFloat {
        switch self {
        case .small: return 0.65
        case .medium: return 1.0
        case .large: return 1.55
        }
    }

    public var smaller: SizeClass {
        switch self {
        case .large: return .medium
        case .medium, .small: return .small
        }
    }

    public var larger: SizeClass {
        switch self {
        case .small: return .medium
        case .medium, .large: return .large
        }
    }
}

/// The preset palette. Chosen to stay legible against both light and dark
/// screenshots, which is why there is no black.
public struct MarkupColor: Equatable, Sendable {
    public let name: String
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat

    public var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: 1) }

    public static let red = MarkupColor(name: "red", red: 0.91, green: 0.15, blue: 0.13)
    public static let orange = MarkupColor(name: "orange", red: 0.98, green: 0.52, blue: 0.09)
    public static let yellow = MarkupColor(name: "yellow", red: 0.98, green: 0.82, blue: 0.11)
    public static let green = MarkupColor(name: "green", red: 0.20, green: 0.75, blue: 0.35)
    public static let blue = MarkupColor(name: "blue", red: 0.16, green: 0.53, blue: 0.96)
    public static let white = MarkupColor(name: "white", red: 1, green: 1, blue: 1)

    public static let palette: [MarkupColor] = [.red, .orange, .yellow, .green, .blue, .white]

    public static func named(_ name: String) -> MarkupColor? {
        palette.first { $0.name == name }
    }

    /// Cycles through the palette for the keyboard shortcut.
    public var next: MarkupColor {
        guard let i = Self.palette.firstIndex(of: self) else { return .red }
        return Self.palette[(i + 1) % Self.palette.count]
    }
}

public struct Style: Equatable, Sendable {
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

    /// Base sizes in screen points, before the size class and backing scale.
    static let baseFontPoints: CGFloat = 15
    static let baseLinePoints: CGFloat = 3

    /// Markup is sized in *screen points*, not as a fraction of the image.
    ///
    /// A screenshot is always viewed at 1:1 against the display it came from,
    /// so annotation on a 1688x202 strip should look the same size as on a
    /// full-window grab. Scaling by the image's short edge instead made markup
    /// collapse to 2px on a wide strip and balloon to 60px on a big window —
    /// an 8x swing driven by nothing but crop shape.
    ///
    /// The only image-dependent part is a ceiling, so markup cannot swamp a
    /// very small crop.
    public static func scaled(to imageSize: CGSize,
                              backingScale: CGFloat = 2,
                              color: MarkupColor = .red,
                              size: SizeClass = .medium) -> Style {
        let scale = backingScale > 0 ? backingScale : 1
        let factor = size.multiplier * scale
        let shortEdge = min(imageSize.width, imageSize.height)

        let font = min(baseFontPoints * factor, max(9, shortEdge * 0.35))
        let line = min(baseLinePoints * factor, max(1, shortEdge * 0.08))

        return Style(color: color.cgColor,
                     lineWidth: max(1, line.rounded()),
                     fontSize: max(9, font.rounded()))
    }
}
