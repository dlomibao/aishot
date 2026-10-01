import AIShotCore
import AppKit

@MainActor
final class EditorWindowController: NSWindowController, CanvasViewDelegate, NSWindowDelegate {
    private let canvas: CanvasView
    private let toolbar = NSStackView()
    private let styleBar = NSStackView()
    private var toolPicker: NSSegmentedControl!
    private var swatches: [SwatchButton] = []
    private var sizeControl: NSSegmentedControl!
    private var copySizeMenu: NSPopUpButton!
    private var zoomMenu: NSPopUpButton!
    private let scrollView = NSScrollView()
    /// Fit mode rescales the image whenever the window changes size. Any manual
    /// zoom leaves it; Zoom to Fit returns to it.
    private var fitsWindow = true
    private var undoButton: NSButton!
    private var redoButton: NSButton!
    private let onFinish: @MainActor (Data?) -> Void
    var onRequestReload: (@MainActor () -> Void)?

    private static let rowHeight: CGFloat = 38
    private static let toolbarHeight: CGFloat = rowHeight * 2
    private static let barMargin: CGFloat = 10

    init(image: CGImage, onFinish: @escaping @MainActor (Data?) -> Void) {
        self.onFinish = onFinish

        let pixelSize = CGSize(width: image.width, height: image.height)
        let canvasSize = Self.canvasSize(for: pixelSize)

        // The canvas is always laid out at actual size; the scroll view's
        // magnification does all the shrinking and enlarging.
        canvas = CanvasView(image: image, frame: NSRect(origin: .zero, size: Self.actualSize(for: pixelSize)))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: canvasSize.width, height: canvasSize.height + Self.toolbarHeight),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
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

    private static var backingScale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    /// The image's size in points at 100%: how big it was on screen.
    private static func actualSize(for imagePixelSize: CGSize) -> CGSize {
        CGSize(width: (imagePixelSize.width / backingScale).rounded(),
               height: (imagePixelSize.height / backingScale).rounded())
    }

    /// The window's opening size: actual size, shrunk to fit the screen.
    private static func canvasSize(for imagePixelSize: CGSize) -> CGSize {
        let maxSize = (NSScreen.main?.visibleFrame.size).map {
            CGSize(width: $0.width * 0.9, height: $0.height * 0.9 - toolbarHeight)
        } ?? CGSize(width: 1200, height: 800)
        return CanvasTransform.preferredCanvasSize(
            imagePixelSize: imagePixelSize,
            backingScale: backingScale,
            maxPointSize: maxSize)
    }

    /// Laid out with constraints rather than hand-computed frames: the toolbar
    /// is pinned to the top edge, so no arithmetic during a resize can put it
    /// somewhere the window does not show.
    private func buildContentView(canvasSize: CGSize) {
        guard let window, let content = window.contentView else { return }

        let bar = NSVisualEffectView()
        bar.material = .titlebar
        bar.blendingMode = .withinWindow
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)
        buildToolRow(in: bar)
        buildStyleRow(in: bar)

        scrollView.contentView = CenteringClipView()
        scrollView.documentView = canvas
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Zoom.minimum
        scrollView.maxMagnification = Zoom.maximum
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .underPageBackgroundColor
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView, positioned: .below, relativeTo: bar)

        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.topAnchor.constraint(equalTo: content.topAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.toolbarHeight),

            scrollView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        // A pinch is a manual zoom, so it ends fit mode like ⌘+ does.
        NotificationCenter.default.addObserver(self, selector: #selector(liveMagnifyStarted(_:)),
                                               name: NSScrollView.willStartLiveMagnifyNotification, object: scrollView)
        NotificationCenter.default.addObserver(self, selector: #selector(liveMagnifyEnded(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)

        resizeWindow(canvasSize: canvasSize, recenter: true)
    }

    private var chromeWidth: CGFloat {
        max(toolbar.fittingSize.width, styleBar.fittingSize.width) + Self.barMargin * 2
    }

    /// Re-run whenever the image's dimensions change, which cropping does.
    /// Later resizes keep the top-left corner where it was: re-centring made
    /// the window jump away from wherever you had moved it.
    private func resizeWindow(canvasSize: CGSize, recenter: Bool) {
        guard let window else { return }
        let width = max(canvasSize.width, chromeWidth).rounded()
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)

        window.contentMinSize = NSSize(width: chromeWidth.rounded(), height: Self.toolbarHeight + 120)
        window.setContentSize(NSSize(width: width, height: canvasSize.height + Self.toolbarHeight))
        window.contentView?.layoutSubtreeIfNeeded()
        fitsWindow = true
        applyFit()

        if recenter {
            window.center()
            return
        }
        var frame = window.frame
        frame.origin = NSPoint(x: topLeft.x, y: topLeft.y - frame.height)
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true)
    }

    private func buildToolRow(in bar: NSView) {
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: Self.barMargin),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -Self.barMargin),
            toolbar.topAnchor.constraint(equalTo: bar.topAnchor, constant: 5),
            toolbar.heightAnchor.constraint(equalToConstant: Self.rowHeight - 10),
        ])

        // A segmented control is the native macOS tool picker: narrow, with a
        // selected state that follows the window's key status on its own. The
        // shortcut sits beside each icon; the name is in the tooltip.
        toolPicker = NSSegmentedControl(images: Tool.toolbarOrder.map { tool in
            NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.label) ?? NSImage()
        }, trackingMode: .selectOne, target: self, action: #selector(toolPicked(_:)))
        for (index, tool) in Tool.toolbarOrder.enumerated() {
            toolPicker.setLabel(tool.shortcut, forSegment: index)
            toolPicker.setToolTip("\(tool.label) — press \(tool.shortcut)", forSegment: index)
        }
        toolPicker.setAccessibilityLabel("Tools")
        toolbar.addArrangedSubview(toolPicker)

        toolbar.addArrangedSubview(NSView())

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.attributedTitle = titleWithHint("Cancel", "esc")
        cancel.bezelStyle = .rounded
        cancel.toolTip = "esc — discard and close, leaving the clipboard alone"
        toolbar.addArrangedSubview(cancel)

        let done = NSButton(title: "Copy", target: self, action: #selector(doneTapped))
        done.attributedTitle = titleWithHint("Copy", "⏎")
        done.bezelStyle = .rounded
        done.toolTip = "⏎ — copy the annotated image and close. ⌘C copies without closing."
        done.keyEquivalent = "\r"
        toolbar.addArrangedSubview(done)
    }

    /// Standard ⌘ shortcuts, so the hint lives in the tooltip rather than
    /// taking toolbar width.
    private func iconButton(_ symbol: String, label: String, tip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(),
                              target: self, action: action)
        button.bezelStyle = .rounded
        button.toolTip = tip
        button.setAccessibilityLabel(label)
        return button
    }

    private func buildStyleRow(in bar: NSView) {
        styleBar.orientation = .horizontal
        styleBar.spacing = 4
        styleBar.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(styleBar)
        NSLayoutConstraint.activate([
            styleBar.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: Self.barMargin),
            styleBar.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -Self.barMargin),
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
        colorHint.setAccessibilityElement(false)
        styleBar.addArrangedSubview(colorHint)

        styleBar.addArrangedSubview(NSView())

        sizeControl = NSSegmentedControl(labels: SizeClass.allCases.map(\.label),
                                         trackingMode: .selectOne,
                                         target: self, action: #selector(sizeChanged(_:)))
        sizeControl.toolTip = "Stroke and text size — [ and ] to step"
        for (index, name) in ["Small", "Medium", "Large"].enumerated() {
            sizeControl.setToolTip(name, forSegment: index)
        }
        sizeControl.setAccessibilityLabel("Markup size")
        styleBar.addArrangedSubview(sizeControl)

        let sizeHint = NSTextField(labelWithString: "[ ]")
        sizeHint.font = .systemFont(ofSize: 10)
        sizeHint.textColor = .tertiaryLabelColor
        sizeHint.setAccessibilityElement(false)
        styleBar.addArrangedSubview(sizeHint)

        styleBar.addArrangedSubview(NSView())

        let copyLabel = NSTextField(labelWithString: "Copy at")
        copyLabel.font = .systemFont(ofSize: 11)
        copyLabel.textColor = .secondaryLabelColor
        copyLabel.setAccessibilityElement(false)
        styleBar.addArrangedSubview(copyLabel)

        copySizeMenu = NSPopUpButton(frame: .zero, pullsDown: false)
        copySizeMenu.controlSize = .small
        copySizeMenu.font = .systemFont(ofSize: 11)
        for size in ExportSize.allCases {
            copySizeMenu.addItem(withTitle: size.label)
            copySizeMenu.lastItem?.representedObject = size.rawValue
        }
        copySizeMenu.selectItem(at: ExportSize.allCases.firstIndex(of: Preferences.copySize) ?? 0)
        copySizeMenu.target = self
        copySizeMenu.action = #selector(copySizeChanged(_:))
        copySizeMenu.toolTip = "Largest edge of the copied image. Vision models bill by pixel area, "
            + "so a smaller copy is cheaper to paste. Save always keeps full resolution."
        copySizeMenu.setAccessibilityLabel("Copied image size")
        styleBar.addArrangedSubview(copySizeMenu)

        zoomMenu = NSPopUpButton(frame: .zero, pullsDown: true)
        zoomMenu.controlSize = .small
        zoomMenu.font = .systemFont(ofSize: 11)
        zoomMenu.addItem(withTitle: "100%")
        for (title, action) in [("Zoom to Fit  ⌘9", #selector(zoomToFit)),
                                ("Actual Size  ⌘0", #selector(zoomToActualSize)),
                                ("Zoom In  ⌘+", #selector(zoomIn)),
                                ("Zoom Out  ⌘−", #selector(zoomOut))] {
            zoomMenu.addItem(withTitle: title)
            zoomMenu.lastItem?.target = self
            zoomMenu.lastItem?.action = action
        }
        zoomMenu.toolTip = "Zoom. Pinch, or ⌘+ and ⌘−. Resizing the window refits until you zoom by hand."
        zoomMenu.setAccessibilityLabel("Zoom")
        styleBar.addArrangedSubview(zoomMenu)
        styleBar.setCustomSpacing(12, after: zoomMenu)

        let reload = iconButton("arrow.clockwise", label: "Reload",
                                tip: "Reload — ⌘V loads the image currently on the clipboard",
                                action: #selector(pasteAction))
        undoButton = iconButton("arrow.uturn.backward", label: "Undo", tip: "Undo — ⌘Z", action: #selector(undoTapped))
        redoButton = iconButton("arrow.uturn.forward", label: "Redo", tip: "Redo — ⇧⌘Z", action: #selector(redoTapped))
        let save = iconButton("square.and.arrow.down", label: "Save",
                              tip: "Save — ⌘S writes a full-resolution PNG and keeps editing",
                              action: #selector(saveAction))
        undoButton.isEnabled = false
        redoButton.isEnabled = false
        styleBar.setCustomSpacing(12, after: copySizeMenu)
        for button in [reload, undoButton!, redoButton!, save] { styleBar.addArrangedSubview(button) }
    }

    @objc private func copySizeChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let size = ExportSize(rawValue: raw) else { return }
        Preferences.copySize = size
        window?.makeFirstResponder(canvas)
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions

    @objc private func toolPicked(_ sender: NSSegmentedControl) {
        guard Tool.toolbarOrder.indices.contains(sender.selectedSegment) else { return }
        select(tool: Tool.toolbarOrder[sender.selectedSegment])
    }

    private func select(tool: Tool) {
        canvas.tool = tool
        refreshToolButtons()
        window?.makeFirstResponder(canvas)
    }

    private func refreshToolButtons() {
        toolPicker.selectedSegment = Tool.toolbarOrder.firstIndex(of: canvas.tool) ?? -1
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
    @objc private func redoTapped() { canvas.redo() }

    /// Edit-menu shortcuts reach the app delegate even while the Save panel's
    /// filename field, or a text box on the canvas, has focus. Those keystrokes
    /// belong to the text, not to the image.
    private var focusedText: NSText? {
        NSApp.keyWindow?.firstResponder as? NSText
    }

    func performUndo() {
        if let text = focusedText { text.undoManager?.undo(); return }
        canvas.undo()
    }

    func performRedo() {
        if let text = focusedText { text.undoManager?.redo(); return }
        canvas.redo()
    }

    /// ⌘C copies without closing, for back-and-forth sessions. Inside a text
    /// field it copies the selected text, as it would anywhere else.
    func copyWithoutClosing() {
        if let text = focusedText {
            text.copy(nil)
            return
        }
        if canvas.hasPendingCrop { canvas.confirmCrop() }
        let size = Preferences.copySize
        guard let png = canvas.exportPNG(size: size) else {
            presentError("Could not render the image.")
            return
        }
        Pasteboard.write(png: png)
        OutputFile.save(png: png)
        window?.subtitle = size == .original ? "Copied" : "Copied at \(size.label)"
    }

    /// ⌘V means "paste text" inside a text field and "load the newer screenshot"
    /// everywhere else.
    @objc func pasteAction() {
        if let text = focusedText {
            text.paste(nil)
            return
        }
        guard confirmDiscardingMarkup() else { return }
        onRequestReload?()
    }

    private func confirmDiscardingMarkup() -> Bool {
        confirmDiscard(title: "Replace this image?",
                       detail: "Loading the clipboard will discard the markup you have already drawn.",
                       action: "Replace")
    }

    private func confirmClosing() -> Bool {
        confirmDiscard(title: "Discard your markup?",
                       detail: "Closing now throws away what you have drawn. Nothing is copied to the clipboard.",
                       action: "Discard")
    }

    private func confirmDiscard(title: String, detail: String, action: String) -> Bool {
        guard canvas.hasMarkup else { return true }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.alertStyle = .warning
        let destructive = alert.addButton(withTitle: action)
        destructive.hasDestructiveAction = true
        // esc must mean "keep editing", or a second esc press discards the work
        // the first one was asking about.
        alert.addButton(withTitle: "Keep Editing").keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Tear down without reporting a result — used when swapping in a new image.
    func discard() {
        hasFinished = true
        window?.orderOut(nil)
        window?.delegate = nil
    }

    /// Unlike Copy, saving is not a terminal action — the window stays up so you
    /// can keep annotating or save a second copy elsewhere.
    @objc func saveAction() {
        if canvas.hasPendingCrop { canvas.confirmCrop() }
        guard let png = canvas.exportPNG() else {
            presentError("Could not render the image.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = OutputFile.suggestedName()
        panel.directoryURL = OutputFile.saveDirectory
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url)
                window.subtitle = "Saved \(url.lastPathComponent)"
            } catch {
                self?.presentError("Could not save to \(url.path): \(error.localizedDescription)")
            }
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Save failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    @objc private func cancelTapped() {
        guard confirmClosing() else { return }
        finish(with: nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmClosing()
    }

    @objc private func doneTapped() {
        // ⏎ resolves whatever is pending before it means "finish the image":
        // committing text, then confirming a crop.
        if canvas.isEditingText {
            canvas.commitPendingText()
            return
        }
        if canvas.hasPendingCrop {
            canvas.confirmCrop()
            return
        }
        finish(with: canvas.exportPNG(size: Preferences.copySize))
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
        redoButton.isEnabled = view.canRedo
        window?.subtitle = ""
    }

    /// A crop (or undoing one) changes the image's dimensions, so the window
    /// has to grow or shrink around it.
    func canvasDidChangeBounds(_ view: CanvasView) {
        canvas.setFrameSize(Self.actualSize(for: view.croppedBounds.size))
        resizeWindow(canvasSize: Self.canvasSize(for: view.croppedBounds.size), recenter: false)
        window?.title = "aishot — \(Int(view.croppedBounds.width))×\(Int(view.croppedBounds.height))"
    }

    // MARK: - Zoom

    private func applyFit() {
        scrollView.layoutSubtreeIfNeeded()
        let magnification = Zoom.fit(document: canvas.frame.size, in: scrollView.contentSize)
        setMagnification(magnification, centeredAt: NSPoint(x: canvas.frame.midX, y: canvas.frame.midY))
    }

    private func setMagnification(_ magnification: CGFloat, centeredAt point: NSPoint) {
        scrollView.setMagnification(Zoom.clamp(magnification), centeredAt: point)
        canvas.needsDisplay = true
        updateZoomLabel()
    }

    /// Zooms around whatever is in the middle of the view, so ⌘+ does not
    /// jump away from the part you were looking at.
    private func zoomByHand(to magnification: CGFloat) {
        fitsWindow = false
        let visible = scrollView.documentVisibleRect
        setMagnification(magnification, centeredAt: NSPoint(x: visible.midX, y: visible.midY))
    }

    @objc func zoomIn() { zoomByHand(to: Zoom.stepIn(from: scrollView.magnification)) }
    @objc func zoomOut() { zoomByHand(to: Zoom.stepOut(from: scrollView.magnification)) }
    @objc func zoomToActualSize() { zoomByHand(to: 1) }

    @objc func zoomToFit() {
        fitsWindow = true
        applyFit()
    }

    private func updateZoomLabel() {
        let label = Zoom.percentLabel(scrollView.magnification)
        zoomMenu?.item(at: 0)?.title = fitsWindow ? "\(label) fit" : label
        zoomMenu?.item(at: 1)?.state = fitsWindow ? .on : .off
    }

    @objc private func liveMagnifyStarted(_ notification: Notification) {
        fitsWindow = false
    }

    @objc private func liveMagnifyEnded(_ notification: Notification) {
        updateZoomLabel()
    }

    func windowDidResize(_ notification: Notification) {
        if fitsWindow { applyFit() }
    }

    // MARK: - Keyboard

    /// Digit keys pick tools; esc cancels. ⌘Z arrives via the app's Edit menu.
    func handle(keyDown event: NSEvent) -> Bool {
        // The save panel and alerts are in-process windows, so this monitor
        // sees their keys too. esc there must close the dialog, not the editor.
        guard let window, event.window === window,
              window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }

        if handleZoomShortcut(event) { return true }

        if canvas.isEditingText {
            if event.keyCode == 53 { canvas.discardPendingText(); return true }
            return false
        }
        // Some other text control has focus; its keys are not tool shortcuts.
        if window.firstResponder is NSText { return false }

        // esc backs out of the smallest thing first: a selection, then a
        // pending crop, and only then the whole editor.
        if event.keyCode == 53 {
            if canvas.clearSelection() { return true }
            if canvas.cancelPendingCrop() { return true }
            cancelTapped()
            return true
        }
        guard !event.modifierFlags.contains(.command) else { return false }

        // Delete and forward-delete remove the selected shape.
        if event.keyCode == 51 || event.keyCode == 117 {
            guard canvas.hasSelection else { return false }
            canvas.deleteSelection()
            return true
        }

        let keys = event.charactersIgnoringModifiers ?? ""
        if let digit = Int(keys), let tool = Tool(rawValue: digit) {
            select(tool: tool)
            return true
        }
        switch keys.lowercased() {
        case "v": select(tool: .select); return true
        // C confirms a pending crop; colour cycling is suppressed until it is
        // resolved, since confirming is the only thing you want at that moment.
        case "c":
            if canvas.hasPendingCrop { canvas.confirmCrop() } else { select(color: canvas.color.next) }
            return true
        case "[": select(size: canvas.sizeClass.smaller); return true
        case "]": select(size: canvas.sizeClass.larger); return true
        default: return false
        }
    }
}

extension EditorWindowController {
    /// ⌘+ is usually typed as ⌘= (no Shift), and a menu key equivalent can
    /// only match one character, so both are caught here.
    func handleZoomShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return false }
        switch event.charactersIgnoringModifiers {
        case "=", "+": zoomIn()
        case "-": zoomOut()
        case "0": zoomToActualSize()
        case "9": zoomToFit()
        default: return false
        }
        return true
    }
}
