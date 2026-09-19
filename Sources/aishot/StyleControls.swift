import AIShotCore
import AppKit

/// A colour swatch that shows its own selection, so the palette reads at a
/// glance without a separate label.
final class SwatchButton: NSButton {
    let markupColor: MarkupColor

    init(color: MarkupColor, target: AnyObject, action: Selector) {
        self.markupColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
        self.target = target
        self.action = action
        isBordered = false
        title = ""
        toolTip = color.name.capitalized
        setContentHuggingPriority(.required, for: .horizontal)
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset: CGFloat = isSelected ? 4 : 3
        let fill = bounds.insetBy(dx: inset, dy: inset)

        ctx.setFillColor(markupColor.cgColor)
        ctx.addPath(CGPath(roundedRect: fill, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()

        // A hairline keeps the white swatch visible against a light toolbar.
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(1)
        ctx.addPath(CGPath(roundedRect: fill.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.strokePath()

        guard isSelected else { return }
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 6, cornerHeight: 6, transform: nil))
        ctx.strokePath()
    }
}

/// Last-used colour and size survive relaunch, which matters because the app
/// quits after every screenshot.
enum Preferences {
    private static let colorKey = "markupColor"
    private static let sizeKey = "markupSize"

    static var color: MarkupColor {
        get { MarkupColor.named(UserDefaults.standard.string(forKey: colorKey) ?? "") ?? .red }
        set { UserDefaults.standard.set(newValue.name, forKey: colorKey) }
    }

    static var sizeClass: SizeClass {
        get { SizeClass(rawValue: UserDefaults.standard.string(forKey: sizeKey) ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sizeKey) }
    }
}
