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
/// Installs execute a ``DependencyDefinition``'s steps against a bottle using
/// only public CorkKit APIs: ``CorkPaths``, ``BottleManager``, ``Downloader`` and
/// the path/argument helpers in ``InstallPlanner``. Non-fatal failures (a failed
/// `reg add`, a non-zero installer exit, a failed DLL copy) are reported as
/// ``InstallEvent/warning`` and execution continues; a download failure and a
/// missing bottle are fatal.
public struct DependencyManager: DependencyInstalling {
    public let paths: CorkPaths

    public init(paths: CorkPaths = .resolve()) {
        self.paths = paths
    }

    /// The full built-in catalog, sorted by component id.
    public func components() -> [DependencyComponent] {
        DependencyCatalog.all.map(\.component)
    }

    /// Look up a component by id (case-insensitive).
    public func component(id: String) -> DependencyComponent? {
        DependencyCatalog.definition(id: id)?.component
    }

    /// The definition (steps) behind a component id, case-insensitively.
    public func definition(id: String) -> DependencyDefinition? {
        DependencyCatalog.definition(id: id)
    }

    public func install(
        componentID: String,
        into bottleName: String,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws {
        guard let definition = DependencyCatalog.definition(id: componentID) else {
            throw CorkError.unsupported(reason: "unknown dependency component '\(componentID)'")
        }

        onEvent(.resolving("\(definition.component.id) → bottle \(bottleName)"))

        let manager = try BottleManager(paths: paths)
        let bottle = try manager.load(named: bottleName)

        let cache = Self.cacheDirectory(paths: paths, bottleName: bottleName)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let userName = InstallPlanner.defaultUserName(driveC: bottle.driveCDirectory)
        let environment = InstallPlanner.windowsEnvironment(driveC: bottle.driveCDirectory, userName: userName)

        for note in definition.notes {
            onEvent(.warning(note))
        }

        for action in DependencyPlanner.plan(definition) {
            try await execute(
                action,
                componentID: definition.component.id,
                bottleName: bottleName,
                bottle: bottle,
                manager: manager,
                cache: cache,
                environment: environment,
                onEvent: onEvent
            )
        }

        if definition.requiresReboot {
            onEvent(.warning(
                "'\(definition.component.id)' requires a reboot; restart the bottle before using it."
            ))
        }
        onEvent(.finished)
    }

    // MARK: - Cache

    /// Per-bottle dependency cache: `<Cork>/Cache/Dependencies/<bottle>`.
    public static func cacheDirectory(paths: CorkPaths, bottleName: String) -> URL {
        let safe = bottleName.map {
            $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "_"
        }
        return paths.cacheDirectory
            .appendingPathComponent("Dependencies", isDirectory: true)
            .appendingPathComponent(String(safe), isDirectory: true)
    }

    // MARK: - Execution

    private func execute(
        _ action: DependencyPlanner.Action,
        componentID: String,
        bottleName: String,
        bottle: Bottle,
        manager: BottleManager,
        cache: URL,
        environment: [String: String],
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws {
        switch action {
        case .setWindowsVersion(let version):
            do {
                _ = try manager.setSetting(
                    named: bottleName,
                    key: BottleSettings.Key.windows.rawValue,
                    value: version
                )
            } catch {
                onEvent(.warning("could not set Windows version to '\(version)': \(describe(error))"))
            }

        case .download(let urlString, let fileName):
            try await performDownload(urlString: urlString, fileName: fileName, cache: cache, onEvent: onEvent)

        case .createDirectory(let windowsPath):
            let path = InstallPlanner.resolveWindowsPath(
                windowsPath,
                driveC: bottle.driveCDirectory,
                environment: environment
            )
            do {
                try FileManager.default.createDirectory(
                    at: URL(fileURLWithPath: path),
                    withIntermediateDirectories: true
                )
            } catch {
                onEvent(.warning("could not create '\(windowsPath)': \(describe(error))"))
            }

        case .runInstaller(let executable, let arguments):
            run(
                command: executable,
                arguments: arguments,
                isInstaller: true,
                bottleName: bottleName,
                bottle: bottle,
                manager: manager,
                cache: cache,
                environment: environment,
                onEvent: onEvent
            )

        case .runCommand(let executable, let arguments):
            run(
                command: executable,
                arguments: arguments,
                isInstaller: false,
                bottleName: bottleName,
                bottle: bottle,
                manager: manager,
                cache: cache,
                environment: environment,
                onEvent: onEvent
            )

        case .registry(let executable, let arguments):
            // `arguments` is [add, key, /v, name, /t, REG_SZ, /d, data, /f].
            let key = arguments.count > 1 ? arguments[1] : componentID
            let name = arguments.count > 3 ? arguments[3] : ""
            onEvent(.registry(name.isEmpty ? key : "\(key)\\\(name)"))
            do {
                let status = try manager.exec(named: bottleName, command: executable, arguments: arguments)
                if status != 0 {
                    onEvent(.warning("'\(executable) \(arguments.joined(separator: " "))' exited with status \(status)"))
                }
            } catch {
                onEvent(.warning("could not run '\(executable)': \(describe(error))"))
            }

        case .copyFile(let source, let destination):
            onEvent(.copying("\(source) → \(destination)"))
            let sourcePath = InstallPlanner.resolveLocalPath(
                source,
                driveC: bottle.driveCDirectory,
                cache: cache,
                environment: environment
            )
            let destinationPath = InstallPlanner.resolveWindowsPath(
                destination,
                driveC: bottle.driveCDirectory,
                environment: environment
            )
            do {
                let url = URL(fileURLWithPath: destinationPath)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.copyItem(at: URL(fileURLWithPath: sourcePath), to: url)
            } catch {
                onEvent(.warning("could not copy '\(source)' to '\(destination)': \(describe(error))"))
            }

        case .manual(let reason):
            onEvent(.warning(reason))
        }
    }

    // MARK: - Steps

    private func performDownload(
        urlString: String,
        fileName: String,
        cache: URL,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws {
        guard let url = URL(string: urlString) else {
            onEvent(.warning("skipping download of invalid URL '\(urlString)'"))
            return
        }

        let destination = cache.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            onEvent(.resolving("using cached \(fileName)"))
            return
        }

        onEvent(.downloading(name: fileName, totalBytes: nil))

        let reportedTotal = OnceFlag()
        try await Downloader.download(from: url, to: destination) { progress in
            if progress.totalBytes > 0, reportedTotal.fire() {
                onEvent(.downloading(name: fileName, totalBytes: progress.totalBytes))
            }
        }
    }

    private func run(
        command: String,
        arguments: [String],
        isInstaller: Bool,
        bottleName: String,
        bottle: Bottle,
        manager: BottleManager,
        cache: URL,
        environment: [String: String],
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) {
        let display = ([command] + arguments).joined(separator: " ")
        onEvent(.running(display))
        do {
            let status: Int32
            if InstallPlanner.commandLooksLikeFile(
                command,
                driveC: bottle.driveCDirectory,
                cache: cache,
                environment: environment
            ) {
                let path = InstallPlanner.resolveLocalPath(
                    command,
                    driveC: bottle.driveCDirectory,
                    cache: cache,
                    environment: environment
                )
                status = try manager.run(
                    named: bottleName,
                    executable: URL(fileURLWithPath: path),
                    arguments: arguments
                )
            } else {
                status = try manager.exec(named: bottleName, command: command, arguments: arguments)
            }
            if status != 0 {
                let kind = isInstaller ? "installer" : "command"
                onEvent(.warning("\(kind) '\(command)' exited with status \(status)"))
            }
        } catch {
            onEvent(.warning("could not run '\(command)': \(describe(error))"))
        }
    }

    private func describe(_ error: Error) -> String {
        if let corkError = error as? CorkError {
            return corkError.errorDescription ?? "\(corkError)"
        }
        return (error as NSError).localizedDescription
    }
}

/// Thread-safe one-shot latch used to report a download's total size exactly once.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if fired { return false }
        fired = true
        return true
    }
}
