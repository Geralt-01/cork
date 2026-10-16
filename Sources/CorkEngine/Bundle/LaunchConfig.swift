import Foundation

/// Metadata written to `Contents/Resources/launch.json` inside a generated
/// `.app`. It records everything needed to launch the Windows program: the
/// bottle, the executable (resolved to a Unix path) and the default arguments.
///
/// The launcher script embeds the same values directly so it does not need a
/// JSON parser at runtime; `launch.json` exists for tooling and inspection
/// (and so a future launcher can read it).
public struct LaunchConfig: Codable, Sendable, Hashable {
    /// Bottle the program runs in.
    public var bottle: String
    /// Unix path to the executable, suitable for `cork run`.
    public var executable: String
    /// The executable exactly as supplied to the bundler (`C:\…` or Unix).
    public var windowsExecutable: String?
    /// Default arguments passed before any user-supplied arguments.
    public var arguments: [String]
    /// Cork version that generated the bundle.
    public var corkVersion: String?

    public init(
        bottle: String,
        executable: String,
        windowsExecutable: String? = nil,
        arguments: [String] = [],
        corkVersion: String? = nil
    ) {
        self.bottle = bottle
        self.executable = executable
        self.windowsExecutable = windowsExecutable
        self.arguments = arguments
        self.corkVersion = corkVersion
    }
}
