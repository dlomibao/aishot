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
        setAccessibilityLabel("\(color.name.capitalized) colour")
        setContentHuggingPriority(.required, for: .horizontal)
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var isSelected = false {
        didSet {
            needsDisplay = true
            setAccessibilityValue(isSelected ? "selected" : nil)
        }
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

/// A button title with its shortcut trailing in smaller, dimmer type. Keeps the
/// hint visible without the width cost of setting it at full size — the toolbar
/// is what sets the window's minimum width.
///
/// An attributed title ignores `contentTintColor`, so a selected button has to
/// get its contrasting colours here to be distinguishable at all. The weight
/// stays the same so selecting a tool never changes the toolbar's width.
func titleWithHint(_ title: String, _ hint: String, selected: Bool = false) -> NSAttributedString {
    let result = NSMutableAttributedString(string: title, attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: selected ? NSColor.white : NSColor.labelColor,
    ])
    result.append(NSAttributedString(string: "  \(hint)", attributes: [
        .font: NSFont.systemFont(ofSize: 10, weight: .medium),
        .foregroundColor: selected ? NSColor.white.withAlphaComponent(0.75) : NSColor.secondaryLabelColor,
    ]))
    return result
}

/// Last-used colour and size survive relaunch, which matters because the app
/// quits after every screenshot.
enum Preferences {
    private static let colorKey = "markupColor"
    private static let sizeKey = "markupSize"
    private static let copySizeKey = "copySize"

    static var color: MarkupColor {
        get { MarkupColor.named(UserDefaults.standard.string(forKey: colorKey) ?? "") ?? .red }
        set { UserDefaults.standard.set(newValue.name, forKey: colorKey) }
    }

    static var copySize: ExportSize {
        get { ExportSize(rawValue: UserDefaults.standard.string(forKey: copySizeKey) ?? "") ?? .defaultForCopy }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: copySizeKey) }
    }

    static var sizeClass: SizeClass {
        get { SizeClass(rawValue: UserDefaults.standard.string(forKey: sizeKey) ?? "") ?? .medium }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: sizeKey) }
    }

}


extension Tool {
    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .box: return "rectangle"
        case .highlight: return "highlighter"
        case .text: return "textformat"
        case .badge: return "1.circle"
        case .redact: return "eye.slash"
        case .crop: return "crop"
        }
    }
}
