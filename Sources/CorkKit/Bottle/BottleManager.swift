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
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: paths.bottlesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .compactMap { try? Bottle.load(at: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func exists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: paths.bottleDirectory(named: name).path)
    }

    public func load(named name: String) throws -> Bottle {
        let url = paths.bottleDirectory(named: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CorkError.bottleNotFound(name: name)
        }
        return try Bottle.load(at: url)
    }

    public func delete(named name: String) throws {
        let url = paths.bottleDirectory(named: name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CorkError.bottleNotFound(name: name)
        }
        if let bottle = try? Bottle.load(at: url), runtime.isWineReady, let installation = try? runtime.requireWine() {
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
        if exists(named: name) {
            if force {
                try delete(named: name)
            } else {
                throw CorkError.bottleAlreadyExists(name: name)
            }
        }

        let installation = try runtime.requireWine()
        try paths.createDirectories()

        var bottle = Bottle(
            url: paths.bottleDirectory(named: name),
            metadata: BottleMetadata(name: name, wineVersion: installation.version() ?? "unknown", settings: settings)
        )
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
        if status != 0 {
            onEvent(.warning("wineboot exited with status \(status) - see \(bootLog.lastPathComponent)"))
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
    }

    public func setSetting(named name: String, key: String, value: String) throws -> Bottle {
        var bottle = try load(named: name)
        try bottle.metadata.settings.apply(key: key, value: value)

        if let installation = try? runtime.requireWine() {
            if key == BottleSettings.Key.windows.rawValue {
                try applyWindowsVersion(bottle.settings.windowsVersion, to: &bottle, installation: installation)
            }
            if key == BottleSettings.Key.backend.rawValue, bottle.settings.backend != .wined3d {
                try graphics.setBackend(bottle.settings.backend, on: &bottle)
            } else if key == BottleSettings.Key.backend.rawValue {
                try graphics.setBackend(.wined3d, on: &bottle)
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
        onLine: (@Sendable (String) -> Void)? = nil
    ) throws -> Int32 {
        let bottle = try load(named: name)
        let installation = try runtime.requireWine()
        guard FileManager.default.fileExists(atPath: executable.path) else {
            throw CorkError.fileSystem(reason: "no such executable: \(executable.path)")
        }

        let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation)
        let logFile = bottle.logsDirectory.appendingPathComponent("run-\(Self.timestamp()).log")

        let wineArguments: [String]
        if detach {
            wineArguments = ["start", "/unix", executable.path] + arguments
        } else {
            wineArguments = [executable.path] + arguments
        }

        return try WineProcess.runStreaming(
            executable: installation.wineBinary,
            arguments: wineArguments,
            environment: environment,
            currentDirectory: executable.deletingLastPathComponent(),
            logFile: logFile,
            onLine: onLine
        )
    }

    @discardableResult
    public func exec(
        named name: String,
        command: String,
        arguments: [String] = [],
        onLine: (@Sendable (String) -> Void)? = nil
    ) throws -> Int32 {
        let bottle = try load(named: name)
        let installation = try runtime.requireWine()

        let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation)
        let logFile = bottle.logsDirectory.appendingPathComponent("run-\(Self.timestamp()).log")

        return try WineProcess.runStreaming(
            executable: installation.wineBinary,
            arguments: [command] + arguments,
            environment: environment,
            logFile: logFile,
            onLine: onLine
        )
    }

    @discardableResult
    public func kill(named name: String) throws -> ProcessResult {
        let bottle = try load(named: name)
        let installation = try runtime.requireWine()
        return try WineProcess.killServer(installation: installation, bottle: bottle)
    }

    private func applyWindowsVersion(
        _ version: WindowsVersion,
        to bottle: inout Bottle,
        installation: WineInstallation
    ) throws {
        let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation)
        let key = "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion"
        let values = [
            ("CurrentVersion", version.registryVersion),
            ("CurrentBuildNumber", version.registryBuild),
        ]
        for (name, value) in values {
            _ = try? WineProcess.runAndWait(
                installation: installation,
                arguments: ["reg", "add", key, "/v", name, "/t", "REG_SZ", "/d", value, "/f"],
                environment: environment
            )
        }
    }

    static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
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
