import AIShotCore
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

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
        // File URLs only: a copied web link would otherwise be fetched here,
        // synchronously, on the main thread.
        let fileOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: fileOptions) as? [URL],
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
    /// Where every copied image is archived automatically.
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Pictures/aishots", isDirectory: true)

    /// Where the Save panel opens. Fixed rather than remembering the last
    /// folder, so the destination is predictable every time.
    static let saveDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads", isDirectory: true)

    static func suggestedName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "aishot-\(formatter.string(from: date)).png"
    }

    /// A disk copy is the fallback for targets that will not take a pasteboard
    /// image but will take a path or a drag.
    @discardableResult
    static func save(png: Data) -> URL? {
        let url = FileNaming.uniqueURL(for: directory.appendingPathComponent(suggestedName()),
                                       exists: { FileManager.default.fileExists(atPath: $0.path) })
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
