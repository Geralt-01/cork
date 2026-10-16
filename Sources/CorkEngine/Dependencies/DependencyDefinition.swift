import CorkKit
import Foundation

/// A single declarative action that installs (part of) a dependency component.
///
/// The vocabulary is deliberately small and mirrors what a bottle can actually
/// do through CorkKit's public APIs: change the prefix Windows version, fetch a
/// payload, create a directory, run a (silent) installer or Wine command, write
/// a registry value, copy a file into the prefix, or explicitly defer to the
/// user because the payload cannot be unpacked automatically.
public enum DependencyStep: Sendable, Hashable, Codable {
    /// Set the bottle's reported Windows version before the next steps run.
    case setWindowsVersion(String)
    /// Download `url` into the per-bottle cache as `fileName`.
    case download(url: String, fileName: String)
    /// Create a directory inside the prefix (a `C:\…` or `%Var%` path).
    case createDirectory(String)
    /// Run a downloaded installer quietly (`arguments` are the silent flags).
    case runInstaller(command: String, arguments: [String])
    /// Run a Wine command (e.g. a self-extractor or `regsvr32`).
    case runCommand(command: String, arguments: [String])
    /// Add a string registry value (`wine reg add …`).
    case registry(key: String, name: String, data: String)
    /// Copy a file from the cache / prefix into the prefix.
    case copyFile(source: String, destination: String)
    /// A step Cork cannot automate; surfaced as an ``InstallEvent/warning``.
    case manual(String)

    /// Short, stable label used to populate ``DependencyComponent/verbs``.
    public var verb: String {
        switch self {
        case .setWindowsVersion: return "setWindowsVersion"
        case .download: return "download"
        case .createDirectory: return "createDirectory"
        case .runInstaller: return "runInstaller"
        case .runCommand: return "runCommand"
        case .registry: return "registry"
        case .copyFile: return "copyFile"
        case .manual: return "manual"
        }
    }

    /// Whether this step needs a network download.
    public var isDownload: Bool {
        if case .download = self { return true }
        return false
    }
}

/// A built-in component paired with the ordered steps that install it.
///
/// `notes` are advisory messages emitted as warnings before execution (e.g.
/// "this installs the whole DirectX 9 runtime"). `requiresReboot` mirrors the
/// installer's own reboot hint.
public struct DependencyDefinition: Sendable, Hashable, Codable {
    public var component: DependencyComponent
    public var steps: [DependencyStep]
    public var requiresReboot: Bool
    public var notes: [String]

    public init(
        component: DependencyComponent,
        steps: [DependencyStep],
        requiresReboot: Bool = false,
        notes: [String] = []
    ) {
        self.component = component
        self.steps = steps
        self.requiresReboot = requiresReboot
        self.notes = notes
    }
}

/// Pure translation of a ``DependencyStep`` into the concrete action an executor
/// performs. Factor out the argument assembly so it can be tested without a
/// Wine runtime or network access.
public enum DependencyPlanner {
    /// A resolved action: Wine invocations are already in their final
    /// `(executable, arguments)` form.
    public enum Action: Sendable, Equatable {
        case setWindowsVersion(String)
        case download(url: String, fileName: String)
        case createDirectory(String)
        case runInstaller(executable: String, arguments: [String])
        case runCommand(executable: String, arguments: [String])
        case registry(executable: String, arguments: [String])
        case copyFile(source: String, destination: String)
        case manual(reason: String)
    }

    /// Resolve one step. Registry steps are rewritten into the exact
    /// `wine reg add …` argument vector.
    public static func action(for step: DependencyStep) -> Action {
        switch step {
        case .setWindowsVersion(let version):
            return .setWindowsVersion(version)
        case .download(let url, let fileName):
            return .download(url: url, fileName: fileName)
        case .createDirectory(let directory):
            return .createDirectory(directory)
        case .runInstaller(let command, let arguments):
            return .runInstaller(executable: command, arguments: arguments)
        case .runCommand(let command, let arguments):
            return .runCommand(executable: command, arguments: arguments)
        case .registry(let key, let name, let data):
            return .registry(
                executable: "reg",
                arguments: InstallPlanner.registryArguments(key: key, name: name, data: data)
            )
        case .copyFile(let source, let destination):
            return .copyFile(source: source, destination: destination)
        case .manual(let reason):
            return .manual(reason: reason)
        }
    }

    /// Resolve every step of a definition, preserving order.
    public static func plan(_ definition: DependencyDefinition) -> [Action] {
        definition.steps.map(action(for:))
    }
}
