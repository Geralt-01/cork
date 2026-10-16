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
    /// - Parameters:
    ///   - name: display name of the app (also the bundle name).
    ///   - bottle: the bottle the program runs in.
    ///   - executable: path to the Windows executable (unix path or `C:\…`).
    ///   - arguments: default arguments.
    ///   - iconPath: optional `.icns`/image to use as the icon.
    ///   - outputDirectory: where to place `<name>.app` (e.g. ~/Applications).
    ///
    /// TODO(bundle): implement bundle generation (Info.plist, launcher script,
    /// icon, `CFBundleIdentifier`).
    public func createBundle(
        name: String,
        bottle: Bottle,
        executable: String,
        arguments: [String] = [],
        iconPath: URL? = nil,
        outputDirectory: URL
    ) throws -> URL {
        _ = (name, bottle, executable, arguments, iconPath, outputDirectory)
        throw CorkError.unsupported(reason: "app bundling is not implemented yet")
    }
}
