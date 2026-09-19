import AIShotCore
import AppKit

@MainActor
final class EditorWindowController: NSWindowController, CanvasViewDelegate, NSWindowDelegate {
    private let canvas: CanvasView
    private let toolbar = NSStackView()
    private let styleBar = NSStackView()
    private var toolButtons: [Tool: NSButton] = [:]
    private var swatches: [SwatchButton] = []
    private var sizeControl: NSSegmentedControl!
    private var undoButton: NSButton!
    private let onFinish: @MainActor (Data?) -> Void
    var onRequestReload: (@MainActor () -> Void)?

    private static let rowHeight: CGFloat = 38
    private static let toolbarHeight: CGFloat = rowHeight * 2
    /// The chrome needs more width than a small crop does, so the window floors
    /// at a width the toolbar actually fits in and centres the canvas.
    private static let minimumWidth: CGFloat = 660

    init(image: CGImage, onFinish: @escaping @MainActor (Data?) -> Void) {
        self.onFinish = onFinish

        let maxSize = (NSScreen.main?.visibleFrame.size).map {
            CGSize(width: $0.width * 0.9, height: $0.height * 0.9 - Self.toolbarHeight)
        } ?? CGSize(width: 1200, height: 800)
        let canvasSize = CanvasTransform.preferredCanvasSize(
            imagePixelSize: CGSize(width: image.width, height: image.height),
            backingScale: NSScreen.main?.backingScaleFactor ?? 2,
            maxPointSize: maxSize)

        canvas = CanvasView(image: image, frame: NSRect(origin: .zero, size: canvasSize))

        let windowWidth = max(canvasSize.width, Self.minimumWidth)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: canvasSize.height + Self.toolbarHeight),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "aishot — \(image.width)×\(image.height)"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        canvas.delegate = self
        buildContentView(canvasSize: canvasSize)
        select(tool: .arrow)
        select(color: Preferences.color)
        select(size: Preferences.sizeClass)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildContentView(canvasSize: CGSize) {
        guard let content = window?.contentView else { return }
        let width = content.bounds.width

        canvas.frame = NSRect(x: ((width - canvasSize.width) / 2).rounded(), y: 0,
                              width: canvasSize.width, height: canvasSize.height)
        content.addSubview(canvas)

        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: canvasSize.height,
                                                   width: width, height: Self.toolbarHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        content.addSubview(bar)

        buildToolRow(in: bar)
        buildStyleRow(in: bar)
    }

    private func buildToolRow(in bar: NSView) {
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -10),
            toolbar.topAnchor.constraint(equalTo: bar.topAnchor, constant: 5),
            toolbar.heightAnchor.constraint(equalToConstant: Self.rowHeight - 10),
        ])

        for tool in Tool.allCases {
            let button = NSButton(title: "\(tool.label)  \(tool.rawValue)", target: self, action: #selector(toolTapped(_:)))
            button.bezelStyle = .rounded
            button.tag = tool.rawValue
            toolButtons[tool] = button
            toolbar.addArrangedSubview(button)
        }

        toolbar.addArrangedSubview(NSView())

        let reload = NSButton(title: "Reload  ⌘V", target: self, action: #selector(pasteAction))
        reload.bezelStyle = .rounded
        reload.toolTip = "Load the image currently on the clipboard"
        toolbar.addArrangedSubview(reload)

        undoButton = NSButton(title: "Undo  ⌘Z", target: self, action: #selector(undoTapped))
        undoButton.bezelStyle = .rounded
        undoButton.isEnabled = false
        toolbar.addArrangedSubview(undoButton)

        let cancel = NSButton(title: "Cancel  esc", target: self, action: #selector(cancelTapped))
        cancel.bezelStyle = .rounded
        toolbar.addArrangedSubview(cancel)

        let done = NSButton(title: "Copy  ⏎", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        toolbar.addArrangedSubview(done)
    }

    private func buildStyleRow(in bar: NSView) {
        styleBar.orientation = .horizontal
        styleBar.spacing = 4
        styleBar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(styleBar)
        NSLayoutConstraint.activate([
            styleBar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            styleBar.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -10),
            styleBar.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -5),
        ])

        for color in MarkupColor.palette {
            let swatch = SwatchButton(color: color, target: self, action: #selector(swatchTapped(_:)))
            swatches.append(swatch)
            styleBar.addArrangedSubview(swatch)
        }

        let colorHint = NSTextField(labelWithString: "C")
        colorHint.font = .systemFont(ofSize: 10)
        colorHint.textColor = .tertiaryLabelColor
        colorHint.toolTip = "Press C to cycle colours"
        styleBar.addArrangedSubview(colorHint)

        styleBar.addArrangedSubview(NSView())

        sizeControl = NSSegmentedControl(labels: SizeClass.allCases.map(\.label),
                                         trackingMode: .selectOne,
                                         target: self, action: #selector(sizeChanged(_:)))
        sizeControl.toolTip = "Stroke and text size — [ and ] to step"
        styleBar.addArrangedSubview(sizeControl)

        let sizeHint = NSTextField(labelWithString: "[ ]")
        sizeHint.font = .systemFont(ofSize: 10)
        sizeHint.textColor = .tertiaryLabelColor
        styleBar.addArrangedSubview(sizeHint)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions

    @objc private func toolTapped(_ sender: NSButton) {
        guard let tool = Tool(rawValue: sender.tag) else { return }
        select(tool: tool)
    }

    private func select(tool: Tool) {
        canvas.tool = tool
        for (candidate, button) in toolButtons {
            button.state = candidate == tool ? .on : .off
            button.bezelStyle = .rounded
            button.contentTintColor = candidate == tool ? .controlAccentColor : nil
        }
        window?.makeFirstResponder(canvas)
    }

    @objc private func swatchTapped(_ sender: SwatchButton) {
        select(color: sender.markupColor)
    }

    @objc private func sizeChanged(_ sender: NSSegmentedControl) {
        let sizes = SizeClass.allCases
        guard sizes.indices.contains(sender.selectedSegment) else { return }
        select(size: sizes[sender.selectedSegment])
    }

    private func select(color: MarkupColor) {
        canvas.color = color
        for swatch in swatches { swatch.isSelected = swatch.markupColor == color }
        Preferences.color = color
        window?.makeFirstResponder(canvas)
    }

    private func select(size: SizeClass) {
        canvas.sizeClass = size
        sizeControl.selectedSegment = SizeClass.allCases.firstIndex(of: size) ?? 1
        Preferences.sizeClass = size
        window?.makeFirstResponder(canvas)
    }

    @objc private func undoTapped() { canvas.undo() }

    /// ⌘V means "paste text" inside a text field and "load the newer screenshot"
    /// everywhere else.
    @objc func pasteAction() {
        if canvas.isEditingText {
            canvas.pasteIntoTextEditor()
            return
        }
        guard confirmDiscardingMarkup() else { return }
        onRequestReload?()
    }

    private func confirmDiscardingMarkup() -> Bool {
        guard canvas.canUndo else { return true }
        let alert = NSAlert()
        alert.messageText = "Replace this image?"
        alert.informativeText = "Loading the clipboard will discard the markup you have already drawn."
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Keep Editing")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Tear down without reporting a result — used when swapping in a new image.
    func discard() {
        hasFinished = true
        window?.orderOut(nil)
        window?.delegate = nil
    }

    func undoTappedFromMenu() { canvas.undo() }

    @objc private func cancelTapped() { finish(with: nil) }

    @objc private func doneTapped() {
        // ⏎ belongs to the text field while one is open, so committing text
        // takes priority over finishing the whole image.
        if canvas.isEditingText {
            canvas.commitPendingText()
            return
        }
        finish(with: canvas.exportPNG())
    }

    private var hasFinished = false


    private func finish(with png: Data?) {
        guard !hasFinished else { return }
        hasFinished = true
        window?.orderOut(nil)
        onFinish(png)
    }

    func windowWillClose(_ notification: Notification) {
        finish(with: nil)
    }

    func canvasDidChange(_ view: CanvasView) {
        undoButton.isEnabled = view.canUndo
    }

    // MARK: - Keyboard

    /// Digit keys pick tools; esc cancels. ⌘Z arrives via the app's Edit menu.
    func handle(keyDown event: NSEvent) -> Bool {
        if canvas.isEditingText {
            if event.keyCode == 53 { canvas.undo(); return true }
            return false
        }
        if event.keyCode == 53 { cancelTapped(); return true }
        guard !event.modifierFlags.contains(.command) else { return false }

        let keys = event.charactersIgnoringModifiers ?? ""
        if let digit = Int(keys), let tool = Tool(rawValue: digit) {
            select(tool: tool)
            return true
        }
        switch keys.lowercased() {
        case "c": select(color: canvas.color.next); return true
        case "[": select(size: canvas.sizeClass.smaller); return true
        case "]": select(size: canvas.sizeClass.larger); return true
        default: return false
        }
    }
}

extension EditorWindowController {
    func performUndo() { undoTappedFromMenu() }
}
