import Foundation

/// Small filesystem helpers for the installer, kept separate for testability.
public enum InstallFileOperations {
    /// Copy a file or directory tree, creating parent directories. If the
    /// destination already exists it is merged (directories) or replaced (files).
    public static func copyItem(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        let sourceIsDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

        if fm.fileExists(atPath: destination.path) {
            let destinationIsDirectory = (try? destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if sourceIsDirectory && destinationIsDirectory {
                for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                    try copyItem(from: child, to: destination.appendingPathComponent(child.lastPathComponent))
                }
                return
            }
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }
}
