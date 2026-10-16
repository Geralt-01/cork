import Foundation

/// A resolved action for a single ``InstallStep``.
///
/// Produced by ``InstallPlanner/plan(_:)``. `WineInstaller` performs these in
/// order. Keeping the translation step pure makes it unit-testable without a
/// Wine runtime.
public enum InstallAction: Sendable, Equatable {
    case download(url: String, fileName: String, extractArchive: Bool)
    case setWindowsVersion(String)
    case run(command: String, arguments: [String], workingDirectory: String?, isInstaller: Bool)
    case copyFiles(source: String, destination: String)
    case createShortcut(target: String, name: String, workingDirectory: String?, arguments: [String])
    case registry(key: String, name: String, data: String)
    case skip(reason: String)
}

/// One step plus the action it resolved to.
public struct PlannedInstallStep: Sendable, Equatable {
    public let index: Int
    public let kind: InstallStepKind
    public let action: InstallAction

    public init(index: Int, kind: InstallStepKind, action: InstallAction) {
        self.index = index
        self.kind = kind
        self.action = action
    }
}

/// Pure translation of an ``InstallRecipe`` into ordered, resolved actions and
/// the path/argument helpers the executor relies on.
public enum InstallPlanner {
    // MARK: - Planning

    /// Resolve every step, preserving recipe order. Steps with missing required
    /// fields become ``InstallAction/skip(reason:)`` rather than throwing.
    public static func plan(_ recipe: InstallRecipe) -> [PlannedInstallStep] {
        recipe.steps.enumerated().map { index, step in
            PlannedInstallStep(index: index, kind: step.kind, action: action(for: step))
        }
    }

    static func action(for step: InstallStep) -> InstallAction {
        switch step.kind {
        case .download:
            guard let url = nonEmpty(step.url) else {
                return .skip(reason: "download step has no url")
            }
            guard let fileName = fileName(forURL: url, explicit: step.fileName) else {
                return .skip(reason: "could not derive a file name from '\(url)'")
            }
            return .download(url: url, fileName: fileName, extractArchive: isZip(fileName))

        case .setWindowsVersion:
            guard let version = nonEmpty(step.windowsVersion) else {
                return .skip(reason: "setWindowsVersion step has no windowsVersion")
            }
            return .setWindowsVersion(version)

        case .runInstaller:
            guard let command = nonEmpty(step.command) else {
                return .skip(reason: "runInstaller step has no command")
            }
            let arguments = step.silentArguments.isEmpty ? step.arguments : step.silentArguments
            return .run(command: command, arguments: arguments, workingDirectory: step.workingDirectory, isInstaller: true)

        case .runCommand:
            guard let command = nonEmpty(step.command) else {
                return .skip(reason: "runCommand step has no command")
            }
            let arguments = step.arguments.isEmpty ? step.silentArguments : step.arguments
            return .run(command: command, arguments: arguments, workingDirectory: step.workingDirectory, isInstaller: false)

        case .copyFiles:
            guard let source = nonEmpty(step.source) else {
                return .skip(reason: "copyFiles step has no source")
            }
            guard let destination = nonEmpty(step.destination) else {
                return .skip(reason: "copyFiles step has no destination")
            }
            return .copyFiles(source: source, destination: destination)

        case .createShortcut:
            guard let spec = ShortcutWriter.spec(for: step, appID: "") else {
                return .skip(reason: "createShortcut step has no target")
            }
            return .createShortcut(
                target: spec.targetWindowsPath,
                name: spec.name,
                workingDirectory: spec.workingDirectoryWindowsPath,
                arguments: spec.arguments
            )

        case .registry:
            guard let key = nonEmpty(step.registryKey) else {
                return .skip(reason: "registry step has no registryKey")
            }
            guard let name = nonEmpty(step.registryName) else {
                return .skip(reason: "registry step has no registryName")
            }
            return .registry(key: key, name: name, data: step.registryData ?? "")
        }
    }

    // MARK: - Download helpers

    /// Derive a safe file name from a download URL, honouring an explicit
    /// override (basename only — never a path).
    public static func fileName(forURL urlString: String, explicit: String?) -> String? {
        if let explicit = nonEmpty(explicit) {
            let base = (explicit as NSString).lastPathComponent
            return base.isEmpty ? nil : base
        }
        guard let url = URL(string: urlString) else { return nil }
        var base = url.lastPathComponent
        if base.isEmpty {
            base = (url.path as NSString).lastPathComponent
        }
        base = base.removingPercentEncoding ?? base
        return base.isEmpty ? nil : base
    }

    public static func isZip(_ fileName: String) -> Bool {
        fileName.lowercased().hasSuffix(".zip")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    // MARK: - Registry

    /// The exact argument vector passed to `wine reg` for a ``InstallStepKind/registry`` step.
    public static func registryArguments(key: String, name: String, data: String) -> [String] {
        ["add", key, "/v", name, "/t", "REG_SZ", "/d", data, "/f"]
    }

    // MARK: - Wine path resolution

    /// Best-effort environment map for expanding `%VAR%` tokens in Windows paths.
    public static func windowsEnvironment(driveC: URL, userName: String) -> [String: String] {
        let user = "C:\\users\\\(userName)"
        return [
            "programfiles": "C:\\Program Files",
            "programfiles(x86)": "C:\\Program Files (x86)",
            "programw6432": "C:\\Program Files",
            "commonprogramfiles": "C:\\Program Files\\Common Files",
            "commonprogramfiles(x86)": "C:\\Program Files (x86)\\Common Files",
            "systemroot": "C:\\windows",
            "windir": "C:\\windows",
            "systemdrive": "C:",
            "programdata": "C:\\ProgramData",
            "userprofile": user,
            "appdata": "\(user)\\AppData\\Roaming",
            "localappdata": "\(user)\\AppData\\Local",
            "temp": "\(user)\\AppData\\Local\\Temp",
            "tmp": "\(user)\\AppData\\Local\\Temp",
            "public": "C:\\users\\Public",
        ]
    }

    /// The Wine user name for a bottle: the macOS user name when a matching
    /// `drive_c/users` directory exists, else the first existing one.
    public static func defaultUserName(driveC: URL) -> String {
        let fm = FileManager.default
        let usersDir = driveC.appendingPathComponent("users", isDirectory: true)
        let current = NSUserName()
        if fm.fileExists(atPath: usersDir.appendingPathComponent(current).path) {
            return current
        }
        if let entries = try? fm.contentsOfDirectory(atPath: usersDir.path) {
            let candidates = entries.filter { !$0.hasPrefix(".") }.sorted()
            if let first = candidates.first { return first }
        }
        return current
    }

    /// Resolve a Windows path (`C:\…`, `%ProgramFiles%\…`) to a unix path inside
    /// the bottle. Already-unix paths are returned standardized.
    public static func resolveWindowsPath(
        _ path: String,
        driveC: URL,
        environment: [String: String]
    ) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        value = expandEnvironment(value, environment: environment)
        value = value.replacingOccurrences(of: "\\", with: "/")

        if value.hasPrefix("~") {
            return (value as NSString).expandingTildeInPath
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).standardizedFileURL.path
        }

        let chars = Array(value)
        if chars.count >= 2, chars[0].isLetter, chars[1] == ":" {
            let letter = String(chars[0]).lowercased()
            let rest = String(chars.dropFirst(2))
            let trimmed = rest.hasPrefix("/") ? String(rest.dropFirst()) : rest
            let base: URL
            if letter == "c" {
                base = driveC
            } else {
                base = driveC.deletingLastPathComponent()
                    .appendingPathComponent("dosdevices", isDirectory: true)
                    .appendingPathComponent("\(letter):", isDirectory: true)
            }
            if trimmed.isEmpty { return base.standardizedFileURL.path }
            return base.appendingPathComponent(trimmed).standardizedFileURL.path
        }

        if value.isEmpty { return driveC.standardizedFileURL.path }
        return driveC.appendingPathComponent(value).standardizedFileURL.path
    }

    /// Resolve a recipe path to a local (unix) path, checking the bottle's
    /// drive_c, the per-bottle download cache and native paths.
    public static func resolveLocalPath(
        _ path: String,
        driveC: URL,
        cache: URL,
        environment: [String: String]
    ) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return (trimmed as NSString).expandingTildeInPath
        }
        if trimmed.contains(":") || trimmed.contains("%") {
            return resolveWindowsPath(trimmed, driveC: driveC, environment: environment)
        }
        let cached = cache.appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: cached.path) {
            return cached.standardizedFileURL.path
        }
        return driveC.appendingPathComponent(trimmed).standardizedFileURL.path
    }

    /// Whether a command should be run as a file (`wine <path>`) rather than a
    /// Wine built-in (`wine <command>`), based on its shape / on-disk presence.
    public static func commandLooksLikeFile(
        _ command: String,
        driveC: URL,
        cache: URL,
        environment: [String: String]
    ) -> Bool {
        if command.contains("/") || command.contains("\\") || command.hasPrefix("%") || command.hasPrefix("~") {
            return true
        }
        let resolved = resolveLocalPath(command, driveC: driveC, cache: cache, environment: environment)
        return FileManager.default.fileExists(atPath: resolved)
    }

    static func expandEnvironment(_ value: String, environment: [String: String]) -> String {
        guard value.contains("%") else { return value }
        var lowered: [String: String] = [:]
        for (key, replacement) in environment { lowered[key.lowercased()] = replacement }

        let chars = Array(value)
        var out = ""
        var index = 0
        while index < chars.count {
            if chars[index] == "%" {
                var end = index + 1
                while end < chars.count && chars[end] != "%" { end += 1 }
                if end < chars.count {
                    let token = String(chars[(index + 1)..<end]).lowercased()
                    if let replacement = lowered[token] {
                        out += replacement
                    } else {
                        out += "%" + String(chars[(index + 1)..<end]) + "%"
                    }
                    index = end + 1
                    continue
                }
            }
            out.append(chars[index])
            index += 1
        }
        return out
    }
}
