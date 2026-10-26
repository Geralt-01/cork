import Foundation

public struct BottleManager {
    public let paths: CorkPaths
    public let runtime: RuntimeManager
    private let graphics: GraphicsInstaller

    public init(paths: CorkPaths, runtime: RuntimeManager) {
        self.paths = paths
        self.runtime = runtime
        self.graphics = GraphicsInstaller(runtime: runtime)
    }

    public init(paths: CorkPaths = .resolve()) throws {
        let runtime = try RuntimeManager(paths: paths)
        self.init(paths: paths, runtime: runtime)
    }

    public func list() -> [Bottle] {
        listWithIssues().bottles
    }

    /// Lists bottles, reporting directories that could not be loaded instead of
    /// silently hiding them.
    public func listWithIssues() -> BottleListing {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: paths.bottlesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return BottleListing() }

        var listing = BottleListing()
        for entry in entries where (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            do {
                listing.bottles.append(try Bottle.load(at: entry))
            } catch {
                listing.issues.append(
                    BottleListing.Issue(
                        directoryName: entry.lastPathComponent,
                        reason: Self.describeLoadError(error)
                    )
                )
            }
        }
        listing.bottles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        listing.issues.sort { $0.directoryName.localizedCaseInsensitiveCompare($1.directoryName) == .orderedAscending }
        return listing
    }

    private static func describeLoadError(_ error: Error) -> String {
        if let corkError = error as? CorkError {
            switch corkError {
            case .bottleNotFound:
                return "missing cork/metadata.json"
            default:
                return corkError.errorDescription ?? "\(corkError)"
            }
        }
        if error is DecodingError {
            return "invalid cork/metadata.json"
        }
        return "\(error)"
    }

    public func exists(named name: String) -> Bool {
        guard (try? Bottle.validateName(name)) != nil else { return false }
        return FileManager.default.fileExists(atPath: paths.bottleDirectory(named: name).path)
    }

    public func load(named name: String) throws -> Bottle {
        try Bottle.validateName(name)
        let url = paths.bottleDirectory(named: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CorkError.bottleNotFound(name: name)
        }
        return try Bottle.load(at: url)
    }

    public func delete(named name: String) throws {
        try Bottle.validateName(name)
        let url = paths.bottleDirectory(named: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CorkError.bottleNotFound(name: name)
        }
        if let bottle = try? Bottle.load(at: url), runtime.isWineReady,
           let installation = try? wineInstallation(for: bottle) {
            _ = try? WineProcess.killServer(installation: installation, bottle: bottle)
        }
        try FileManager.default.removeItem(at: url)
    }

    public func create(
        named name: String,
        settings: BottleSettings = BottleSettings(),
        force: Bool = false,
        onEvent: @escaping @Sendable (BottleCreateEvent) -> Void = { _ in },
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> Bottle {
        try Bottle.validateName(name)
        // Existing bottles are rejected before any runtime work, but `force`
        // resolves the runtime and graphics component before deleting the old
        // bottle: a guaranteed failure must not destroy working data.
        if exists(named: name), !force {
            throw CorkError.bottleAlreadyExists(name: name)
        }
        let installation = try runtime.requireWine()
        try requireBackendInstalled(settings.backend)
        try paths.createDirectories()
        if force, exists(named: name) {
            try delete(named: name)
        }

        var bottle = Bottle(
            url: paths.bottleDirectory(named: name),
            metadata: BottleMetadata(name: name, wineVersion: installation.version() ?? "unknown", settings: settings)
        )
        do {
            try FileManager.default.createDirectory(at: bottle.corkDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: bottle.logsDirectory, withIntermediateDirectories: true)
            try bottle.save()

            onEvent(.bootstrappingPrefix)
            let bootLog = bottle.logsDirectory.appendingPathComponent("wineboot-\(Self.timestamp()).log")
            let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation)
            let status = try WineProcess.runStreaming(
                executable: installation.winebootBinary,
                arguments: ["-u"],
                environment: environment,
                logFile: bootLog,
                onLine: onLine
            )
            guard status == 0 else {
                throw CorkError.processFailed(command: "wineboot -u", status: status)
            }
            // `wineboot` can return before wineserver flushes the new prefix's
            // registry files, so wait briefly for them instead of failing a
            // perfectly good prefix.
            guard await waitForPrefixInitialization(of: bottle) else {
                throw CorkError.fileSystem(
                    reason: "Wine did not create a usable prefix (see \(bootLog.lastPathComponent))"
                )
            }

            onEvent(.applyingWindowsVersion)
            try applyWindowsVersion(settings.windowsVersion, to: &bottle, installation: installation)

            onEvent(.installingGraphics(settings.backend))
            if settings.backend != .wined3d {
                try graphics.setBackend(settings.backend, on: &bottle)
            }

            try bottle.save()
            onEvent(.created(bottle.url.path))
            return bottle
        } catch {
            // Do not leave a half-initialized bottle (or, when `force` was used,
            // a directory that looks valid but is not) behind.
            try? FileManager.default.removeItem(at: bottle.url)
            throw error
        }
    }

    /// Waits for `system.reg` and `drive_c` to appear. Wine writes the registry
    /// when wineserver shuts down, which can happen just after `wineboot`
    /// exits, so a fixed check races with prefix creation.
    private func waitForPrefixInitialization(of bottle: Bottle, timeout: TimeInterval = 60) async -> Bool {
        let fm = FileManager.default
        let registry = bottle.url.appendingPathComponent("system.reg")
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if fm.fileExists(atPath: registry.path), fm.fileExists(atPath: bottle.driveCDirectory.path) {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return fm.fileExists(atPath: registry.path)
            && fm.fileExists(atPath: bottle.driveCDirectory.path)
    }

    /// Fails fast when the requested graphics backend is not installed.
    private func requireBackendInstalled(_ backend: GraphicsBackend) throws {
        guard let id = backend.requiresComponentID else { return }
        guard let component = runtime.manifest.component(id: id) else {
            throw CorkError.componentUnknown(id: id)
        }
        guard runtime.store.isInstalled(component) else {
            throw CorkError.componentNotInstalled(id: id, version: component.version)
        }
    }

    public func setSetting(named name: String, key: String, value: String) throws -> Bottle {
        var bottle = try load(named: name)
        try bottle.metadata.settings.apply(key: key, value: value)

        let touchesPrefix = key == BottleSettings.Key.windows.rawValue
            || key == BottleSettings.Key.backend.rawValue
        if touchesPrefix {
            let installation = try wineInstallation(for: bottle)
            if key == BottleSettings.Key.windows.rawValue {
                try applyWindowsVersion(bottle.settings.windowsVersion, to: &bottle, installation: installation)
            }
            if key == BottleSettings.Key.backend.rawValue {
                try graphics.setBackend(bottle.settings.backend, on: &bottle)
            }
        }

        try bottle.save()
        return bottle
    }

    public func setBackend(named name: String, backend: GraphicsBackend) throws -> Bottle {
        var bottle = try load(named: name)
        try graphics.setBackend(backend, on: &bottle)
        try bottle.save()
        return bottle
    }

    @discardableResult
    public func run(
        named name: String,
        executable: URL,
        arguments: [String] = [],
        detach: Bool = false,
        workingDirectory: URL? = nil,
        extraEnvironment: [String: String] = [:],
        onLine: (@Sendable (String) -> Void)? = nil
    ) throws -> Int32 {
        let bottle = try load(named: name)
        return try run(
            bottle: bottle,
            executable: executable,
            arguments: arguments,
            detach: detach,
            workingDirectory: workingDirectory,
            extraEnvironment: extraEnvironment,
            onLine: onLine
        )
    }

    /// Run a program using a user-supplied path. Unlike the `URL` overload,
    /// this accepts Windows paths (`C:\…`, `%ProgramFiles%\…`) and bare names
    /// inside `drive_c`, resolving them against the bottle's prefix.
    @discardableResult
    public func run(
        named name: String,
        executablePath: String,
        arguments: [String] = [],
        detach: Bool = false,
        workingDirectory: URL? = nil,
        extraEnvironment: [String: String] = [:],
        onLine: (@Sendable (String) -> Void)? = nil
    ) throws -> Int32 {
        let bottle = try load(named: name)
        let executable = bottle.resolveExecutablePath(executablePath)
        return try run(
            bottle: bottle,
            executable: executable,
            arguments: arguments,
            detach: detach,
            workingDirectory: workingDirectory,
            extraEnvironment: extraEnvironment,
            onLine: onLine
        )
    }

    private func run(
        bottle: Bottle,
        executable: URL,
        arguments: [String],
        detach: Bool,
        workingDirectory: URL?,
        extraEnvironment: [String: String],
        onLine: (@Sendable (String) -> Void)?
    ) throws -> Int32 {
        let installation = try wineInstallation(for: bottle)
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw CorkError.fileSystem(
                reason: "no such executable: \(executable.path)\n"
                    + "  Cork accepts Unix paths and Windows paths inside the bottle (for example "
                    + #""C:\Program Files\App\app.exe" or "%ProgramFiles%\App\app.exe")."#
            )
        }

        let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation)
            .merging(extraEnvironment) { _, override in override }
        let logFile = bottle.logsDirectory.appendingPathComponent("run-\(Self.timestamp()).log")
        let isMSI = executable.pathExtension.lowercased() == "msi"

        if detach {
            // Spawn and return immediately. Waiting for a launcher such as
            // `wine start` (or for `msiexec` to finish) would make `--detach`
            // behave like a blocking run.
            let wineArguments: [String]
            if isMSI {
                let msiPath = bottle.windowsPath(forLocalPath: executable.path)
                wineArguments = ["msiexec", "/i", msiPath] + arguments
            } else {
                wineArguments = ["start", "/unix", executable.path] + arguments
            }
            try WineProcess.launchDetached(
                executable: installation.wineBinary,
                arguments: wineArguments,
                environment: environment,
                currentDirectory: workingDirectory ?? executable.deletingLastPathComponent(),
                logFile: logFile
            )
            return 0
        }

        let wineArguments: [String]
        if isMSI {
            // `wine setup.msi` does not run the installer; hand it to msiexec.
            // msiexec needs a Windows path: a Unix path starting with `/` is
            // parsed as another switch and silently ignored.
            let msiPath = bottle.windowsPath(forLocalPath: executable.path)
            wineArguments = ["msiexec", "/i", msiPath] + arguments
        } else {
            wineArguments = [executable.path] + arguments
        }

        return try WineProcess.runStreaming(
            executable: installation.wineBinary,
            arguments: wineArguments,
            environment: environment,
            currentDirectory: workingDirectory ?? executable.deletingLastPathComponent(),
            logFile: logFile,
            onLine: onLine
        )
    }

    @discardableResult
    public func exec(
        named name: String,
        command: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        extraEnvironment: [String: String] = [:],
        onLine: (@Sendable (String) -> Void)? = nil
    ) throws -> Int32 {
        let bottle = try load(named: name)
        let installation = try wineInstallation(for: bottle)

        let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation)
            .merging(extraEnvironment) { _, override in override }
        let logFile = bottle.logsDirectory.appendingPathComponent("run-\(Self.timestamp()).log")

        return try WineProcess.runStreaming(
            executable: installation.wineBinary,
            arguments: [command] + arguments,
            environment: environment,
            currentDirectory: workingDirectory,
            logFile: logFile,
            onLine: onLine
        )
    }

    @discardableResult
    public func kill(named name: String) throws -> ProcessResult {
        let bottle = try load(named: name)
        let installation = try wineInstallation(for: bottle)
        return try WineProcess.killServer(installation: installation, bottle: bottle)
    }

    /// The Wine installation a bottle should run with.
    ///
    /// Prefers the version recorded in the bottle's metadata (so a bottle stays
    /// pinned to its Wine build when several are installed), falling back to the
    /// runtime default when that version is unknown or no longer installed.
    private func wineInstallation(for bottle: Bottle) throws -> WineInstallation {
        let recorded = bottle.metadata.wineVersion
        if !recorded.isEmpty, let installation = try? runtime.requireWine(version: recorded) {
            return installation
        }
        return try runtime.requireWine()
    }

    private func applyWindowsVersion(
        _ version: WindowsVersion,
        to bottle: inout Bottle,
        installation: WineInstallation
    ) throws {
        let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation)

        // Prefer Wine's own configurator. `winecfg /v <version>` updates every
        // value Windows consults (CurrentVersion, CurrentBuild, the
        // CurrentMajor/MinorVersionNumber DWORDs, CSDVersion, …) and applies the
        // matching Wine defaults. Writing only CurrentVersion leaves the DWORDs
        // from the prefix's previous version in place, so `ver` keeps reporting
        // the old version after `cork bottle set windows=win7`.
        let configured = try? WineProcess.runAndWait(
            installation: installation,
            arguments: ["winecfg", "/v", version.wineVersion],
            environment: environment
        )
        if configured?.succeeded == true { return }

        // Fallback for Wine builds where winecfg cannot run (for example a
        // headless session). Write the values Wine reads, including the DWORDs.
        let key = "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion"
        let values: [(name: String, value: String, type: String)] = [
            ("CurrentVersion", version.registryVersion, "REG_SZ"),
            ("CurrentBuild", version.registryBuild, "REG_SZ"),
            ("CurrentBuildNumber", version.registryBuild, "REG_SZ"),
            ("CurrentMajorVersionNumber", String(version.registryMajor), "REG_DWORD"),
            ("CurrentMinorVersionNumber", String(version.registryMinor), "REG_DWORD"),
        ]
        var lastStatus: Int32?
        for entry in values {
            let result = try? WineProcess.runAndWait(
                installation: installation,
                arguments: [
                    "reg", "add", key,
                    "/v", entry.name,
                    "/t", entry.type,
                    "/d", entry.value,
                    "/f",
                ],
                environment: environment
            )
            if result?.succeeded != true {
                lastStatus = result?.status ?? -1
            }
        }
        if let lastStatus {
            throw CorkError.processFailed(
                command: "reg add \(key) (requested \(version.rawValue))",
                status: lastStatus
            )
        }
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Milliseconds keep back-to-back runs from sharing (and partially
        // overwriting) the same log file.
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }
}

public enum BottleCreateEvent: Sendable {
    case bootstrappingPrefix
    case applyingWindowsVersion
    case installingGraphics(GraphicsBackend)
    case warning(String)
    case created(String)
}

public struct BottleListing: Sendable {
    public struct Issue: Sendable {
        public let directoryName: String
        public let reason: String

        public init(directoryName: String, reason: String) {
            self.directoryName = directoryName
            self.reason = reason
        }
    }

    public var bottles: [Bottle]
    public var issues: [Issue]

    public init(bottles: [Bottle] = [], issues: [Issue] = []) {
        self.bottles = bottles
        self.issues = issues
    }
}
