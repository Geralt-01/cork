import CorkKit
import Foundation

/// Converts a user-supplied image into `Contents/Resources/AppIcon.icns`.
///
/// An existing `.icns` is copied verbatim; any other image is converted with
/// `/usr/bin/sips` (to build the required PNG sizes) and `/usr/bin/iconutil`
/// (to assemble the `.icns`). Failures throw so the caller can warn and carry
/// on without an icon rather than failing the whole bundle.
enum IconConverter {
    /// Builds `AppIcon.icns` in `resourcesDirectory` from `iconPath`.
    static func makeICNS(from iconPath: URL, in resourcesDirectory: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: iconPath.path) else {
            throw CorkError.fileSystem(reason: "icon not found: \(iconPath.path)")
        }

        let destination = resourcesDirectory.appendingPathComponent("AppIcon.icns")

        if iconPath.pathExtension.lowercased() == "icns" {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: iconPath, to: destination)
            return
        }

        let root = try buildIconset(from: iconPath)
        defer { try? fm.removeItem(at: root) }
        let iconset = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)

        do {
            try run("/usr/bin/iconutil", ["-c", "icns", "-o", destination.path, iconset.path])
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
        guard fm.fileExists(atPath: destination.path) else {
            throw CorkError.fileSystem(reason: "iconutil did not produce \(destination.path)")
        }
    }

    /// The canonical `AppIcon.iconset` members: (filename, pixel size).
    private static let members: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    private static func buildIconset(from image: URL) throws -> URL {
        let fm = FileManager.default
        // Build inside the temporary directory; never write outside output.
        let root = fm.temporaryDirectory
            .appendingPathComponent("cork-icon-\(UUID().uuidString)", isDirectory: true)
        let iconset = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

        for member in members {
            let out = iconset.appendingPathComponent(member.name)
            try run("/usr/bin/sips", [
                "-z", String(member.pixels), String(member.pixels),
                image.path,
                "--out", out.path,
            ])
        }
        return root
    }

    private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CorkError.processFailed(
                command: "\(executable) \(arguments.joined(separator: " "))",
                status: process.terminationStatus
            )
        }
    }
}
