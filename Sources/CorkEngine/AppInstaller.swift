import CorkKit
import Foundation

/// Progress events emitted while installing an application.
public enum InstallEvent: Sendable {
    case resolving(String)
    case downloading(name: String, totalBytes: Int64?)
    case running(String)
    case copying(String)
    case shortcut(String)
    case registry(String)
    case warning(String)
    case finished
}

/// Installs a Windows application into a Cork bottle by executing an
/// ``InstallRecipe``.
///
/// NOTE: frozen CorkEngine API surface.
public protocol AppInstalling: Sendable {
    func install(
        recipe: InstallRecipe,
        into bottleName: String,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws
}

/// Executes a recipe against a bottle using Wine, the managed runtime and
/// Cork's bottle APIs.
///
/// TODO(install-b): implement step execution (download → run installer with
/// per-app Windows version + dll overrides → copy files → create shortcuts →
/// registry), invoked through `cork install`.
public struct WineInstaller: AppInstalling {
    public let paths: CorkPaths

    public init(paths: CorkPaths = .resolve()) {
        self.paths = paths
    }

    public func install(
        recipe: InstallRecipe,
        into bottleName: String,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws {
        _ = recipe
        _ = bottleName
        throw CorkError.unsupported(reason: "the install engine is not implemented yet")
    }
}
