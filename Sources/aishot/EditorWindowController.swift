import AIShotCore
import AppKit

@MainActor
final class EditorWindowController: NSWindowController, CanvasViewDelegate, NSWindowDelegate {
    private let canvas: CanvasView
    private let toolbar = NSStackView()
    private var toolButtons: [Tool: NSButton] = [:]
    private var undoButton: NSButton!
    private let onFinish: @MainActor (Data?) -> Void

    private static let toolbarHeight: CGFloat = 44

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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height + Self.toolbarHeight),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "aishot — \(image.width)×\(image.height)"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self
        canvas.delegate = self
        buildContentView(canvasSize: canvasSize)
        select(tool: .arrow)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func buildContentView(canvasSize: CGSize) {
        guard let content = window?.contentView else { return }
        canvas.frame = NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height)
        canvas.autoresizingMask = [.width, .height]
        content.addSubview(canvas)

        let bar = NSVisualEffectView(frame: NSRect(x: 0, y: canvasSize.height,
                                                   width: canvasSize.width, height: Self.toolbarHeight))
        bar.autoresizingMask = [.width, .minYMargin]
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        content.addSubview(bar)

        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -10),
            toolbar.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])

        for tool in Tool.allCases {
            let button = NSButton(title: "\(tool.label)  \(tool.rawValue)", target: self, action: #selector(toolTapped(_:)))
            button.bezelStyle = .rounded
            button.tag = tool.rawValue
            toolButtons[tool] = button
            toolbar.addArrangedSubview(button)
        }

        toolbar.addArrangedSubview(NSView())

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

    @objc private func undoTapped() { canvas.undo() }

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
        if let digit = Int(event.charactersIgnoringModifiers ?? ""), let tool = Tool(rawValue: digit) {
            select(tool: tool)
            return true
        }
        return false
    }
}

extension EditorWindowController {
    func performUndo() { undoTappedFromMenu() }
}
