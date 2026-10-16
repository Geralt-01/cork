import ArgumentParser
import CorkEngine
import CorkKit
import Foundation

/// Wrap a Windows program in a bottle into a native macOS `.app` bundle.
///
/// NOTE: the bundling track owns this file and completes the implementation.
struct BundleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bundle",
        abstract: "Create a macOS .app that launches a Windows program in a bottle.",
        discussion: """
        The bundle is self-contained: it records the bottle and executable and \
        delegates to 'cork run' at launch time, so Wine can be installed later.
        """
    )

    @Argument(help: "Name of the bottle.")
    var bottle: String

    @Argument(help: "Path to the Windows executable (unix path or C:\\…).")
    var executable: String

    @Option(name: .long, help: "Display name for the app (defaults to the executable name).")
    var name: String?

    @Option(name: .long, help: "Output directory (defaults to ~/Applications).")
    var to: String?

    @Option(name: .long, help: "Icon file (.icns or image) to use.")
    var icon: String?

    func run() async throws {
        let manager = try BottleManager()
        let loadedBottle = try manager.load(named: bottle)

        let appName = name ?? defaultName(for: executable)
        guard !appName.isEmpty else {
            throw ValidationError("Could not infer an app name from '\(executable)'; pass --name.")
        }

        let output = URL(
            fileURLWithPath: ((to as NSString?)?.expandingTildeInPath)
                ?? NSHomeDirectory().appending("/Applications"),
            isDirectory: true
        )

        var iconURL: URL?
        if let icon {
            let url = URL(fileURLWithPath: (icon as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ValidationError("No icon file at \(url.path)")
            }
            iconURL = url
        }

        let bundler = AppBundler()
        let url = try bundler.createBundle(
            name: appName,
            bottle: loadedBottle,
            executable: executable,
            iconPath: iconURL,
            outputDirectory: output
        )

        // Apply the bottle's file-type associations to the new bundle so the
        // generated .app opens the documents its programs are registered for.
        let registered = (try? AssociationStore().registerInBundle(url, bottle: bottle)) ?? []

        print(Terminal.check("Created \(url.path)"))
        if !registered.isEmpty {
            print(Terminal.dim("  file associations: \(registered.joined(separator: ", "))"))
        }
        print(Terminal.dim("  launch with: open \"\(url.path)\""))
    }

    /// Basename of the executable without its extension, supporting both Unix
    /// and `C:\…` paths.
    private func defaultName(for executable: String) -> String {
        let normalized = executable
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let base = (normalized as NSString).lastPathComponent
        let stem = (base as NSString).deletingPathExtension
        return stem.isEmpty ? base : stem
    }
}
