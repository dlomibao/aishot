import AIShotCore
import AppKit

/// Reads whatever image is on the clipboard, lets you mark it up, and puts the
/// result back. The app never captures — macOS's own ⌃⇧⌘4 does that.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: EditorWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenu()
        installKeyMonitor()
        presentEditor()
    }

    /// Relaunching while a window is open should surface it, not stack another.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if controller == nil { presentEditor() } else { controller?.show() }
        return true
    }

    private func presentEditor() {
        guard let image = Pasteboard.readImage() else {
            reportNoImage()
            NSApp.terminate(nil)
            return
        }
        show(image: image)
    }

    private func show(image: CGImage) {
        let controller = EditorWindowController(image: image) { [weak self] png in
            self?.finish(png: png)
        }
        controller.onRequestReload = { [weak self] in self?.reloadFromClipboard() }
        self.controller = controller
        controller.show()
    }

    /// Swap in whatever is on the clipboard now. A fresh window rather than a
    /// mutated one, so a differently sized screenshot still gets sized correctly.
    private func reloadFromClipboard() {
        guard let image = Pasteboard.readImage() else {
            NSSound.beep()
            reportNoImage()
            return
        }
        controller?.discard()
        controller = nil
        show(image: image)
    }

    private func finish(png: Data?) {
        if let png {
            Pasteboard.write(png: png)
            OutputFile.save(png: png)
        }
        controller = nil
        NSApp.terminate(nil)
    }

    private func reportNoImage() {
        let alert = NSAlert()
        alert.messageText = "No image on the clipboard"
        alert.informativeText = "Take a screenshot to the clipboard with ⌃⇧⌘4, then run aishot again."
        alert.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func installKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let controller = self?.controller else { return event }
            return controller.handle(keyDown: event) ? nil : event
        }
    }

    /// A minimal menu exists so the standard ⌘Z / ⌘Q key equivalents work.
    private func installMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit aishot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Save As…", action: #selector(saveAs), keyEquivalent: "s")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(undoAnnotation), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "New Image from Clipboard", action: #selector(pasteFromClipboard), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    @objc private func undoAnnotation() {
        controller?.performUndo()
    }

    @objc private func pasteFromClipboard() {
        controller?.pasteAction()
    }

    @objc private func saveAs() {
        controller?.saveAction()
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
