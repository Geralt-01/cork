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
    /// A distinct 64-bit download URL for a `.download` step, when the catalog
    /// lists both `<downloadurl>` and `<downloadurl64>`.
    ///
    /// Documented rule: Cork emits a single `.download` step for the primary
    /// URL and exposes the 64-bit alternative here — it cannot know the
    /// bottle's architecture at recipe-build time, so it does not queue both.
    public var downloadURL64: String?
    /// Environment variables (name → value) that apply while running the step,
    /// from `<preinstallenvironment>` / `<installerenvironment>`.
    public var environment: [String: String]
    /// True when the step needs removable installation media (a CD/DVD) that
    /// Cork cannot fetch; a human must insert the disc before it can run.
    public var requiresMedia: Bool
    /// The media marker file (`<cdglob><glob>`) that identifies the disc.
    public var mediaPath: String?

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
        description: String? = nil,
        downloadURL64: String? = nil,
        environment: [String: String] = [:],
        requiresMedia: Bool = false,
        mediaPath: String? = nil
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
        self.downloadURL64 = downloadURL64
        self.environment = environment
        self.requiresMedia = requiresMedia
        self.mediaPath = mediaPath
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
    /// Apps this recipe depends on (`<predependency>`), surfaced for callers
    /// that want to check/install them separately.
    public var predependencies: [String]

    public init(
        appID: String,
        steps: [InstallStep] = [],
        requiresReboot: Bool = false,
        dllOverrides: [String] = [],
        predependencies: [String] = []
    ) {
        self.appID = appID
        self.steps = steps
        self.requiresReboot = requiresReboot
        self.dllOverrides = dllOverrides
        self.predependencies = predependencies
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
/// The catalog is streamed once, at initialization, into a compact index of
/// install-relevant fields (see `CrossTieInstallParser`). Recipes are then built
/// on demand, so repeated lookups are cheap and memory stays bounded.
public struct CrossTieInstallRecipes: InstallRecipeProviding {
    public let fileURL: URL
    private let index: CrossTieInstallIndex

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.index = try CrossTieInstallParser.parse(fileURL: fileURL)
    }

    /// The install recipe for `appID`, or `nil` when the catalog has no install
    /// content for it (metadata-only apps, unknown ids, self-closing profiles).
    public func installRecipe(appID: String) -> InstallRecipe? {
        var visited = Set<String>()
        return buildRecipe(appID: appID, visited: &visited)
    }

    /// Build the recipe for `appID`, resolving **every** `<installerid>`
    /// reference recursively.
    ///
    /// `<installerid>` points at another app whose installer actually performs
    /// the install (e.g. Microsoft Word 2000 → Microsoft Office 2000, or Word
    /// 2002 → Office XP). A host may list several ids; each is expanded.
    ///
    /// `visited` is shared across the whole traversal, so every app id is
    /// expanded at most once per lookup. That both breaks reference cycles
    /// (A → B → A) and dedupes diamond references (A → B → D, A → C → D), so
    /// dependency steps never repeat.
    ///
    /// Ordering matches CrossTie semantics: dependencies' steps first, then the
    /// host's own non-installer steps (Windows version, registry, …), and only
    /// then the host's own download / run-installer step(s).
    private func buildRecipe(appID: String, visited: inout Set<String>) -> InstallRecipe? {
        guard !visited.contains(appID), let record = index.record(for: appID) else { return nil }
        visited.insert(appID)

        var dependencySteps: [InstallStep] = []
        var requiresReboot = false
        var dllOverrides: [String] = []
        var predependencies = record.predependencies

        for installerID in record.installerIDs where installerID != appID {
            guard let referenced = buildRecipe(appID: installerID, visited: &visited) else { continue }
            dependencySteps.append(contentsOf: referenced.steps)
            requiresReboot = requiresReboot || referenced.requiresReboot
            for override in referenced.dllOverrides where !dllOverrides.contains(override) {
                dllOverrides.append(override)
            }
            for dependency in referenced.predependencies where !predependencies.contains(dependency) {
                predependencies.append(dependency)
            }
        }

        let ownSteps = record.installSteps()
        let steps: [InstallStep]
        if dependencySteps.isEmpty {
            // No indirection: keep the record's natural step order untouched.
            steps = ownSteps
        } else {
            let isInstallerStep: (InstallStep) -> Bool = { $0.kind == .download || $0.kind == .runInstaller }
            let preamble = ownSteps.filter { !isInstallerStep($0) }
            let installers = ownSteps.filter(isInstallerStep)
            steps = dependencySteps + preamble + installers
        }

        requiresReboot = requiresReboot || record.requiresReboot
        for override in record.dllOverrides where !dllOverrides.contains(override) {
            dllOverrides.append(override)
        }

        guard !steps.isEmpty || requiresReboot || !dllOverrides.isEmpty else { return nil }
        return InstallRecipe(
            appID: appID,
            steps: steps,
            requiresReboot: requiresReboot,
            dllOverrides: dllOverrides,
            predependencies: predependencies
        )
    }
}
