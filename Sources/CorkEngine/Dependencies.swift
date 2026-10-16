import CorkKit
import Foundation

/// A winetricks-style dependency component that can be installed into a bottle.
///
/// NOTE: frozen CorkEngine API surface (the GUI and CLI consume this type).
public struct DependencyComponent: Sendable, Hashable, Codable {
    /// Stable identifier, e.g. `vcrun2015`, `dotnet48`, `d3dx9`.
    public var id: String
    public var name: String
    public var summary: String?
    public var category: String
    /// Wine verbs or documented steps used to perform the install.
    public var verbs: [String]
    /// Windows versions this component is known to work with, if restricted.
    public var windowsVersions: [String]
    /// Whether the component downloads payloads from the network.
    public var requiresDownload: Bool

    public init(
        id: String,
        name: String,
        summary: String? = nil,
        category: String = "Other",
        verbs: [String] = [],
        windowsVersions: [String] = [],
        requiresDownload: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.verbs = verbs
        self.windowsVersions = windowsVersions
        self.requiresDownload = requiresDownload
    }
}

/// Installs dependency components into bottles.
///
/// NOTE: frozen CorkEngine API surface.
public protocol DependencyInstalling: Sendable {
    func components() -> [DependencyComponent]
    func component(id: String) -> DependencyComponent?
    func install(
        componentID: String,
        into bottleName: String,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws
}

/// Dependency engine. Catalog is a built-in, Cork-authored set of components —
/// no third-party data is bundled.
///
/// TODO(deps): implement component catalog + install execution (downloads,
/// registry, DLL copies, per-component Windows version handling).
public struct DependencyManager: DependencyInstalling {
    public let paths: CorkPaths

    public init(paths: CorkPaths = .resolve()) {
        self.paths = paths
    }

    public func components() -> [DependencyComponent] { [] }

    public func component(id: String) -> DependencyComponent? { nil }

    public func install(
        componentID: String,
        into bottleName: String,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws {
        _ = (componentID, bottleName, onEvent)
        throw CorkError.unsupported(reason: "dependency installation is not implemented yet")
    }
}
