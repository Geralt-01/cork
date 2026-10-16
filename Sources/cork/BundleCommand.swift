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
        abstract: "Create a macOS .app that launches a Windows program in a bottle."
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
        let loaded = try manager.load(named: bottle)
        let appName = name ?? URL(fileURLWithPath: executable).deletingPathExtension().lastPathComponent
        let output = URL(fileURLWithPath: ((to as NSString?)?.expandingTildeInPath)
            ?? NSHomeDirectory().appending("/Applications"))
        let iconURL = icon.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let bundler = AppBundler()
        let url = try bundler.createBundle(
            name: appName,
            bottle: loaded,
            executable: executable,
            iconPath: iconURL,
            outputDirectory: output
        )
        print(Terminal.check("Created \(url.path)"))
    }
}
