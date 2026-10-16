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
/// The recipe is first translated into ordered, resolved ``InstallAction``s by
/// ``InstallPlanner``; each action is then executed in order:
///
/// * ``InstallStepKind/download`` — download into a per-bottle cache directory
///   (and extract `.zip`s best-effort).
/// * ``InstallStepKind/setWindowsVersion`` — `bottle set windows=<version>`.
/// * ``InstallStepKind/runInstaller`` / ``InstallStepKind/runCommand`` — through
///   ``BottleManager``, preferring silent arguments for installers.
/// * ``InstallStepKind/copyFiles`` — into the bottle's `drive_c`.
/// * ``InstallStepKind/createShortcut`` — see ``ShortcutWriter``.
/// * ``InstallStepKind/registry`` — `wine reg add …`.
///
/// Non-fatal failures (a failed `reg add`, a missing shortcut target, an
/// unsupported `.zip` on this build, …) are reported as ``InstallEvent/warning``
/// and execution continues. Download failures and a missing bottle are fatal.
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
        onEvent(.resolving("recipe \(recipe.appID) → bottle \(bottleName)"))

        let manager = try BottleManager(paths: paths)
        let bottle = try manager.load(named: bottleName)

        let cache = Self.cacheDirectory(paths: paths, bottleName: bottleName)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let userName = InstallPlanner.defaultUserName(driveC: bottle.driveCDirectory)
        let environment = InstallPlanner.windowsEnvironment(driveC: bottle.driveCDirectory, userName: userName)

        if !recipe.dllOverrides.isEmpty {
            onEvent(.warning(
                "this recipe requests DLL overrides (\(recipe.dllOverrides.joined(separator: ", "))); "
                + "Cork applies graphics overrides per-bottle, so these are not applied automatically."
            ))
        }

        let plan = InstallPlanner.plan(recipe)
        for step in plan {
            try await execute(
                step,
                recipe: recipe,
                bottleName: bottleName,
                bottle: bottle,
                manager: manager,
                cache: cache,
                userName: userName,
                environment: environment,
                onEvent: onEvent
            )
        }

        if recipe.requiresReboot {
            onEvent(.warning("'\(recipe.appID)' may require a reboot; restart the bottle before using it."))
        }
        onEvent(.finished)
    }

    // MARK: - Cache

    /// Per-bottle download cache: `<Cork>/Cache/Installs/<bottle>`.
    public static func cacheDirectory(paths: CorkPaths, bottleName: String) -> URL {
        let safe = bottleName.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." ? $0 : "_" }
        return paths.cacheDirectory
            .appendingPathComponent("Installs", isDirectory: true)
            .appendingPathComponent(String(safe), isDirectory: true)
    }

    // MARK: - Execution

    private func execute(
        _ step: PlannedInstallStep,
        recipe: InstallRecipe,
        bottleName: String,
        bottle: Bottle,
        manager: BottleManager,
        cache: URL,
        userName: String,
        environment: [String: String],
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws {
        switch step.action {
        case .skip(let reason):
            onEvent(.warning("skipping \(step.kind.rawValue) step: \(reason)"))

        case .download(let urlString, let fileName, let extract):
            try await performDownload(
                urlString: urlString,
                fileName: fileName,
                extract: extract,
                cache: cache,
                onEvent: onEvent
            )

        case .setWindowsVersion(let version):
            do {
                _ = try manager.setSetting(named: bottleName, key: BottleSettings.Key.windows.rawValue, value: version)
            } catch {
                onEvent(.warning("could not set Windows version to '\(version)': \(describe(error))"))
            }

        case .run(let command, let arguments, _, let isInstaller):
            let shown = resolvedDisplayName(command, bottle: bottle, cache: cache, environment: environment)
            onEvent(.running(([shown] + arguments).joined(separator: " ")))
            do {
                let status = try runProcess(
                    command: command,
                    arguments: arguments,
                    bottleName: bottleName,
                    bottle: bottle,
                    manager: manager,
                    cache: cache,
                    environment: environment
                )
                if status != 0 {
                    let kind = isInstaller ? "installer" : "command"
                    onEvent(.warning("\(kind) '\(command)' exited with status \(status)"))
                }
            } catch {
                onEvent(.warning("could not run '\(command)': \(describe(error))"))
            }

        case .copyFiles(let source, let destination):
            onEvent(.copying("\(source) → \(destination)"))
            let sourcePath = InstallPlanner.resolveLocalPath(source, driveC: bottle.driveCDirectory, cache: cache, environment: environment)
            let destinationPath = InstallPlanner.resolveWindowsPath(destination, driveC: bottle.driveCDirectory, environment: environment)
            do {
                try InstallFileOperations.copyItem(
                    from: URL(fileURLWithPath: sourcePath),
                    to: URL(fileURLWithPath: destinationPath)
                )
            } catch {
                onEvent(.warning("could not copy '\(source)' to '\(destination)': \(describe(error))"))
            }

        case .createShortcut:
            performShortcut(
                step: step,
                recipe: recipe,
                bottleName: bottleName,
                bottle: bottle,
                manager: manager,
                userName: userName,
                environment: environment,
                onEvent: onEvent
            )

        case .registry(let key, let name, let data):
            onEvent(.registry("\(key)\\\(name)"))
            do {
                let status = try manager.exec(
                    named: bottleName,
                    command: "reg",
                    arguments: InstallPlanner.registryArguments(key: key, name: name, data: data)
                )
                if status != 0 {
                    onEvent(.warning("'reg add \(key)\\\(name)' exited with status \(status)"))
                }
            } catch {
                onEvent(.warning("could not add registry value '\(key)\\\(name)': \(describe(error))"))
            }
        }
    }

    // MARK: - Steps

    /// The file a command resolves to, for progress output: an `<installerglob>`
    /// such as `7z92*.exe` is shown as the real installer name (`7z920.exe`).
    /// Non-file commands (`cmd`, `winecfg`, …) are shown unchanged.
    private func resolvedDisplayName(
        _ command: String,
        bottle: Bottle,
        cache: URL,
        environment: [String: String]
    ) -> String {
        guard InstallPlanner.commandLooksLikeFile(
            command,
            driveC: bottle.driveCDirectory,
            cache: cache,
            environment: environment
        ) else { return command }
        let path = InstallPlanner.resolveLocalPath(
            command,
            driveC: bottle.driveCDirectory,
            cache: cache,
            environment: environment
        )
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func performDownload(
        urlString: String,
        fileName: String,
        extract: Bool,
        cache: URL,
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) async throws {
        guard let url = URL(string: urlString) else {
            onEvent(.warning("skipping download of invalid URL '\(urlString)'"))
            return
        }
        let destination = cache.appendingPathComponent(fileName)
        onEvent(.downloading(name: fileName, totalBytes: nil))

        let reportedTotal = OnceFlag()
        try await Downloader.download(from: url, to: destination) { progress in
            if progress.totalBytes > 0, reportedTotal.fire() {
                onEvent(.downloading(name: fileName, totalBytes: progress.totalBytes))
            }
        }

        guard extract else { return }
        let extractionRoot = cache.appendingPathComponent(
            destination.deletingPathExtension().lastPathComponent,
            isDirectory: true
        )
        do {
            try Archive.extract(archive: destination, to: extractionRoot, format: .zip)
        } catch {
            onEvent(.warning("could not extract '\(fileName)': \(describe(error))"))
        }
    }

    private func runProcess(
        command: String,
        arguments: [String],
        bottleName: String,
        bottle: Bottle,
        manager: BottleManager,
        cache: URL,
        environment: [String: String]
    ) throws -> Int32 {
        if InstallPlanner.commandLooksLikeFile(command, driveC: bottle.driveCDirectory, cache: cache, environment: environment) {
            let path = InstallPlanner.resolveLocalPath(
                command,
                driveC: bottle.driveCDirectory,
                cache: cache,
                environment: environment
            )
            return try manager.run(named: bottleName, executable: URL(fileURLWithPath: path), arguments: arguments)
        }
        return try manager.exec(named: bottleName, command: command, arguments: arguments)
    }

    private func performShortcut(
        step: PlannedInstallStep,
        recipe: InstallRecipe,
        bottleName: String,
        bottle: Bottle,
        manager: BottleManager,
        userName: String,
        environment: [String: String],
        onEvent: @escaping @Sendable (InstallEvent) -> Void
    ) {
        guard case .createShortcut = step.action,
              let spec = ShortcutWriter.spec(
                  for: shortcutStep(for: step, recipe: recipe),
                  appID: recipe.appID,
                  userName: userName
              ) else {
            onEvent(.warning("skipping shortcut step: no resolvable target"))
            return
        }

        onEvent(.shortcut(spec.name))

        if createShortcutViaWine(spec, bottleName: bottleName, bottle: bottle, manager: manager) {
            return
        }

        // Fallback: write the minimal `.lnk` directly (no runtime required).
        let linkPath = InstallPlanner.resolveWindowsPath(
            spec.linkWindowsPath,
            driveC: bottle.driveCDirectory,
            environment: environment
        )
        do {
            let url = URL(fileURLWithPath: linkPath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ShortcutWriter.minimalLink(spec).write(to: url, options: .atomic)
            onEvent(.warning(
                "created a minimal .lnk for '\(spec.name)'; it may lack an icon or full shell metadata."
            ))
        } catch {
            onEvent(.warning("could not create shortcut '\(spec.name)': \(describe(error))"))
        }
    }

    /// Reconstruct the original step so ``ShortcutWriter`` can inspect optional
    /// fields that ``InstallAction`` intentionally drops.
    private func shortcutStep(for planned: PlannedInstallStep, recipe: InstallRecipe) -> InstallStep {
        guard planned.index >= 0, planned.index < recipe.steps.count else {
            return InstallStep(kind: .createShortcut)
        }
        return recipe.steps[planned.index]
    }

    /// Faithful shortcut creation via Wine's `WScript.Shell`. Returns `false`
    /// when the runtime is unavailable or `cscript` fails.
    private func createShortcutViaWine(
        _ spec: ShortcutSpec,
        bottleName: String,
        bottle: Bottle,
        manager: BottleManager
    ) -> Bool {
        let tempDirectory = bottle.driveCDirectory.appendingPathComponent("cork/tmp", isDirectory: true)
        let scriptName = "cork-shortcut-\(UUID().uuidString).vbs"
        let scriptURL = tempDirectory.appendingPathComponent(scriptName)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            try Data(ShortcutWriter.vbsScript(for: spec).utf8).write(to: scriptURL, options: .atomic)
        } catch {
            return false
        }

        let windowsPath = "C:\\cork\\tmp\\\(scriptName)"
        guard let status = try? manager.exec(
            named: bottleName,
            command: "cscript",
            arguments: ["//nologo", "//B", windowsPath]
        ) else {
            return false
        }
        return status == 0
    }

    private func describe(_ error: Error) -> String {
        if let corkError = error as? CorkError {
            return corkError.errorDescription ?? "\(corkError)"
        }
        return (error as NSError).localizedDescription
    }
}

/// Thread-safe one-shot latch used to report download totals exactly once.
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
