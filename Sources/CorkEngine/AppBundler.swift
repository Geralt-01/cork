import CorkKit
import Foundation

/// Generates a native macOS `.app` bundle that launches a Windows program inside
/// a Cork bottle — so a Windows app appears in Finder/Dock like a Mac app.
///
/// NOTE: frozen CorkEngine API surface.
public struct AppBundler: Sendable {
    public let paths: CorkPaths

    public init(paths: CorkPaths = .resolve()) {
        self.paths = paths
    }

    /// Create a `.app` bundle. Returns the URL of the created bundle.
    ///
    /// The produced bundle has the layout:
    /// ```
    /// <name>.app/
    ///   Contents/
    ///     Info.plist              CFBundle* keys, LSMinimumSystemVersion, …
    ///     PkgInfo                 "APPL????"
    ///     MacOS/<name>            executable bash launcher (0755)
    ///     Resources/launch.json   bottle + executable + default args
    ///     Resources/AppIcon.icns  optional icon
    /// ```
    ///
    /// The launcher is a shell script that invokes `cork run` and resolves the
    /// Wine runtime at *launch* time (see ``BundleLauncher``). Creating a bundle
    /// therefore never requires a Wine runtime to be installed.
    ///
    /// - Parameters:
    ///   - name: display name of the app (also the bundle name).
    ///   - bottle: the bottle the program runs in.
    ///   - executable: path to the Windows executable (unix path or `C:\…`).
    ///   - arguments: default arguments.
    ///   - iconPath: optional `.icns`/image to use as the icon.
    ///   - outputDirectory: where to place `<name>.app` (e.g. ~/Applications).
    ///
    /// If `<name>.app` already exists it is replaced, so bundling the same app
    /// twice is idempotent rather than an error.
    public func createBundle(
        name: String,
        bottle: Bottle,
        executable: String,
        arguments: [String] = [],
        iconPath: URL? = nil,
        outputDirectory: URL
    ) throws -> URL {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateBundleName(displayName)

        let fm = FileManager.default
        let output = URL(
            fileURLWithPath: (outputDirectory.path as NSString).expandingTildeInPath,
            isDirectory: true
        )
        try fm.createDirectory(at: output, withIntermediateDirectories: true)

        let bundleURL = output.appendingPathComponent("\(displayName).app", isDirectory: true)
        try ensureInside(output, bundleURL)

        if fm.fileExists(atPath: bundleURL.path) {
            try fm.removeItem(at: bundleURL)
        }

        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try fm.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // Icon first: only advertise CFBundleIconFile when the .icns exists.
        var iconProduced = false
        if let iconPath {
            let icon = URL(fileURLWithPath: (iconPath.path as NSString).expandingTildeInPath)
            do {
                try IconConverter.makeICNS(from: icon, in: resourcesURL)
                iconProduced = true
            } catch {
                warn("could not create app icon from \(icon.path): \(describe(error))")
            }
        }

        let unixExecutable = WindowsPathResolver.resolve(executable, in: bottle)

        let plist = infoPlist(name: displayName, iconProduced: iconProduced)
        try write(propertyList: plist, to: contentsURL.appendingPathComponent("Info.plist"))
        try writePkgInfo(to: contentsURL.appendingPathComponent("PkgInfo"))

        let config = LaunchConfig(
            bottle: bottle.name,
            executable: unixExecutable,
            windowsExecutable: executable,
            arguments: arguments,
            corkVersion: CorkVersion.current
        )
        try writeJSON(config, to: resourcesURL.appendingPathComponent("launch.json"))

        let launcher = macOSURL.appendingPathComponent(displayName, isDirectory: false)
        let script = BundleLauncher.script(
            appName: displayName,
            bottle: bottle.name,
            executable: unixExecutable,
            arguments: arguments
        )
        try Data(script.utf8).write(to: launcher)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launcher.path)

        return bundleURL
    }

    // MARK: - Validation

    private func validateBundleName(_ name: String) throws {
        let invalid: Bool
        if name.isEmpty || name == "." || name == ".." {
            invalid = true
        } else if name.contains("/") || name.contains("\\") || name.contains(":") {
            invalid = true
        } else if name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
            invalid = true
        } else {
            invalid = false
        }
        guard !invalid else {
            throw CorkError.fileSystem(reason: "invalid app name '\(name)'")
        }
    }

    /// Defensive check: the bundle must land directly inside `output`.
    ///
    /// Compares the candidate's parent rather than a string prefix: on macOS
    /// `standardizedFileURL` canonicalizes `/private/var` to `/var` for paths
    /// that exist, but leaves the not-yet-created leaf untouched, so a prefix
    /// check on the full candidate path gives false negatives.
    private func ensureInside(_ output: URL, _ candidate: URL) throws {
        let base = output.standardizedFileURL.path
        let parent = candidate.deletingLastPathComponent().standardizedFileURL.path
        guard parent == base else {
            throw CorkError.fileSystem(reason: "refusing to write outside \(base)")
        }
    }

    // MARK: - Info.plist

    private func infoPlist(name: String, iconProduced: Bool) -> [String: Any] {
        var plist: [String: Any] = [
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": "tools.cork.app.\(Self.slugify(name))",
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
            "CFBundleSignature": "????",
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleShortVersionString": CorkVersion.current,
            "CFBundleVersion": CorkVersion.current,
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": true,
        ]
        if iconProduced {
            plist["CFBundleIconFile"] = "AppIcon"
        }
        return plist
    }

    /// Lowercase, dash-separated slug suitable for a bundle identifier.
    static func slugify(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        let parts = text.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "app" : slug
    }

    // MARK: - Writing

    private func write(propertyList: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: propertyList, format: .xml, options: 0)
        try data.write(to: url)
    }

    private func writeJSON(_ config: LaunchConfig, to url: URL) throws {
        try JSONEncoder.cork.encode(config).write(to: url)
    }

    private func writePkgInfo(to url: URL) throws {
        try Data("APPL????".utf8).write(to: url)
    }

    private func warn(_ message: String) {
        FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
    }

    private func describe(_ error: Error) -> String {
        if let corkError = error as? CorkError {
            return corkError.errorDescription ?? "\(corkError)"
        }
        return "\(error)"
    }
}
