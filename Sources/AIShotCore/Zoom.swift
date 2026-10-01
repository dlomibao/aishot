import CoreGraphics

/// Zoom levels for the editor. A magnification of 1 shows the screenshot at the
/// size it had on screen.
public enum Zoom {
    public static let minimum: CGFloat = 0.1
    public static let maximum: CGFloat = 8

    /// The steps ⌘+ and ⌘- move between, so repeated presses land on round
    /// numbers instead of drifting by a fixed factor.
    public static let steps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    /// The magnification that shows the whole document inside the viewport.
    /// Unlike the window's opening size, this does enlarge a small image, so a
    /// window dragged bigger shows the screenshot bigger.
    public static func fit(document: CGSize, in viewport: CGSize) -> CGFloat {
        guard document.width > 0, document.height > 0, viewport.width > 0, viewport.height > 0 else { return 1 }
        return clamp(min(viewport.width / document.width, viewport.height / document.height))
    }

    /// Strictly larger than `current`, even if `current` sits between steps.
    public static func stepIn(from current: CGFloat) -> CGFloat {
        steps.first { $0 > current + 0.001 } ?? maximum
    }

    /// Strictly smaller than `current`, even if `current` sits between steps.
    public static func stepOut(from current: CGFloat) -> CGFloat {
        steps.last { $0 < current - 0.001 } ?? minimum
    }

    public static func clamp(_ magnification: CGFloat) -> CGFloat {
        min(max(magnification, minimum), maximum)
    }

    public static func percentLabel(_ magnification: CGFloat) -> String {
        "\(Int((magnification * 100).rounded()))%"
    }
}
