import Foundation

public enum FileNaming {
    /// Returns `url`, or `name-2.ext`, `name-3.ext`, … — the first that does
    /// not exist. Two copies in the same second share a timestamp, and the
    /// second write must not overwrite the first.
    public static func uniqueURL(for url: URL, exists: (URL) -> Bool) -> URL {
        guard exists(url) else { return url }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"
            let candidate = directory.appendingPathComponent(name)
            if !exists(candidate) { return candidate }
            n += 1
        }
    }
}
