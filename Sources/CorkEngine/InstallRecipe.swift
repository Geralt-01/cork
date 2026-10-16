import Foundation

/// The kind of action a recipe step performs.
public enum InstallStepKind: String, Sendable, Codable, Hashable {
    case download
    case runInstaller
    case runCommand
    case copyFiles
    case createShortcut
    case registry
    case setWindowsVersion
}

/// A single action in an application install recipe.
///
/// NOTE: frozen CorkEngine API surface. Add fields with defaults only.
public struct InstallStep: Sendable, Hashable, Codable {
    public var kind: InstallStepKind
    /// Download URL (`.download`).
    public var url: String?
    /// Destination file name for a download.
    public var fileName: String?
    /// Executable / Wine command to run (`.runInstaller`, `.runCommand`).
    public var command: String?
    /// Arguments for the above.
    public var arguments: [String]
    /// Silent-install arguments.
    public var silentArguments: [String]
    /// Working directory (Wine path or unix path).
    public var workingDirectory: String?
    /// Source path for `.copyFiles`.
    public var source: String?
    /// Destination path for `.copyFiles` / shortcut target for `.createShortcut`.
    public var destination: String?
    /// Registry key (`.registry`).
    public var registryKey: String?
    /// Registry value name.
    public var registryName: String?
    /// Registry value data.
    public var registryData: String?
    /// Windows version to apply (`.setWindowsVersion`), e.g. `winxp`.
    public var windowsVersion: String?
    /// Human-readable description.
    public var description: String?

    public init(
        kind: InstallStepKind,
        url: String? = nil,
        fileName: String? = nil,
        command: String? = nil,
        arguments: [String] = [],
        silentArguments: [String] = [],
        workingDirectory: String? = nil,
        source: String? = nil,
        destination: String? = nil,
        registryKey: String? = nil,
        registryName: String? = nil,
        registryData: String? = nil,
        windowsVersion: String? = nil,
        description: String? = nil
    ) {
        self.kind = kind
        self.url = url
        self.fileName = fileName
        self.command = command
        self.arguments = arguments
        self.silentArguments = silentArguments
        self.workingDirectory = workingDirectory
        self.source = source
        self.destination = destination
        self.registryKey = registryKey
        self.registryName = registryName
        self.registryData = registryData
        self.windowsVersion = windowsVersion
        self.description = description
    }
}

/// An ordered set of steps that installs one Windows application into a bottle.
///
/// NOTE: frozen CorkEngine API surface.
public struct InstallRecipe: Sendable, Hashable, Codable {
    public var appID: String
    public var steps: [InstallStep]
    public var requiresReboot: Bool
    public var dllOverrides: [String]

    public init(
        appID: String,
        steps: [InstallStep] = [],
        requiresReboot: Bool = false,
        dllOverrides: [String] = []
    ) {
        self.appID = appID
        self.steps = steps
        self.requiresReboot = requiresReboot
        self.dllOverrides = dllOverrides
    }
}

/// Provides install recipes for application ids.
///
/// NOTE: frozen CorkEngine API surface.
public protocol InstallRecipeProviding: Sendable {
    func installRecipe(appID: String) -> InstallRecipe?
}

/// Extracts install recipes from a user-supplied CrossTie catalog.
///
/// TODO(install-a): implement step extraction from `<installprofile>` /
/// `<preinstallregistry>` / `<filestocopy>` / `<lnkfile>` / `<downloadurl>`.
public struct CrossTieInstallRecipes: InstallRecipeProviding {
    public let fileURL: URL

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
    }

    public func installRecipe(appID: String) -> InstallRecipe? {
        _ = appID
        return nil
    }
}
