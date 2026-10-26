import Foundation

public enum Archive {
    public enum Format: String {
        case tarXz = "tar.xz"
        case tarGz = "tar.gz"
        case tarBz2 = "tar.bz2"
        case tar = "tar"
        case zip = "zip"

        public var isTar: Bool {
            self != .zip
        }
    }

    public static func listEntries(archive: URL, format: Format = .tar) throws -> [String] {
        let executable: String
        let arguments: [String]
        switch format {
        case .zip:
            executable = "/usr/bin/unzip"
            arguments = ["-Z1", archive.path]
        default:
            executable = "/usr/bin/tar"
            arguments = ["-tf", archive.path]
        }
        let result = try ProcessRunner.run(executable: executable, arguments: arguments)
        guard result.succeeded else {
            let tool = format == .zip ? "unzip -Z1" : "tar -tf"
            throw CorkError.extractionFailed(reason: "\(tool) failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    public static func validateEntries(_ entries: [String]) throws {
        for entry in entries {
            if entry.isEmpty { continue }
            if entry.hasPrefix("/") {
                throw CorkError.archiveUnsafe(reason: "absolute path '\(entry)'")
            }
            if entry.contains("\0") {
                throw CorkError.archiveUnsafe(reason: "entry contains a null byte")
            }
            let components = entry.split(separator: "/", omittingEmptySubsequences: false)
            if components.contains("..") {
                throw CorkError.archiveUnsafe(reason: "parent traversal in '\(entry)'")
            }
        }
    }

    public static func extract(
        archive: URL,
        to destination: URL,
        installRoot: String? = nil,
        format: Format
    ) throws {
        let entries = try listEntries(archive: archive, format: format)
        try validateEntries(entries)

        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let staging = parent.appendingPathComponent(".cork-extract-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        let result: ProcessResult
        switch format {
        case .zip:
            // `-o` overwrites staging files without prompting; the staging
            // directory is always fresh, so there is nothing to preserve.
            result = try ProcessRunner.run(
                executable: "/usr/bin/unzip",
                arguments: ["-q", "-o", archive.path, "-d", staging.path]
            )
        default:
            result = try ProcessRunner.run(
                executable: "/usr/bin/tar",
                arguments: ["-xf", archive.path, "-C", staging.path]
            )
        }
        guard result.succeeded else {
            throw CorkError.extractionFailed(reason: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        try assertNoEscapingLinks(in: staging)

        var source = staging
        if let installRoot, !installRoot.isEmpty {
            source = staging.appendingPathComponent(installRoot, isDirectory: true)
            let resolved = source.standardizedFileURL.path
            let rootPath = staging.standardizedFileURL.path
            guard resolved.hasPrefix(rootPath + "/") else {
                throw CorkError.archiveUnsafe(reason: "install root '\(installRoot)' escapes the archive")
            }
            guard fm.fileExists(atPath: source.path) else {
                throw CorkError.extractionFailed(reason: "install root '\(installRoot)' not found in archive")
            }
        }

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.moveItem(at: source, to: destination)
    }

    public static func assertNoEscapingLinks(in root: URL) throws {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
            options: []
        ) else { return }

        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink == true else { continue }

            let destination = try fm.destinationOfSymbolicLink(atPath: url.path)
            let resolved: String
            if destination.hasPrefix("/") {
                resolved = destination
            } else {
                resolved = url.deletingLastPathComponent()
                    .appendingPathComponent(destination)
                    .standardizedFileURL.path
            }
            if !resolved.hasPrefix(rootPath + "/") && resolved != rootPath {
                throw CorkError.archiveUnsafe(reason: "symlink '\(url.lastPathComponent)' escapes the archive root")
            }
        }
    }
}
