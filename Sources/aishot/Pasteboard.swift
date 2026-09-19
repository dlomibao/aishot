import AIShotCore
import AppKit
import CoreGraphics

enum Pasteboard {
    /// Screenshots arrive as PNG or TIFF depending on how they were copied.
    /// Prefer PNG so nothing is resampled on the way in.
    static func readImage() -> CGImage? {
        let pb = NSPasteboard.general
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pb.data(forType: type),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return image
            }
        }
        // Fall back to a copied image file (Finder, or ⇧⌘4 saved to disk).
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let url = urls.first,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return nil
    }

    static func write(png: Data) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(png, forType: .png)
    }
}

enum OutputFile {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/aishots", isDirectory: true)

    static func suggestedName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "aishot-\(formatter.string(from: date)).png"
    }

    /// A disk copy is the fallback for targets that will not take a pasteboard
    /// image but will take a path or a drag.
    @discardableResult
    static func save(png: Data) -> URL? {
        let url = directory.appendingPathComponent(suggestedName())
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: url)
            return url
        } catch {
            NSLog("aishot: could not write \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
}
