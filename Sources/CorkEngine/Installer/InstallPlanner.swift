import Foundation

/// A resolved action for a single ``InstallStep``.
///
/// Produced by ``InstallPlanner/plan(_:)``. `WineInstaller` performs these in
/// order. Keeping the translation step pure makes it unit-testable without a
/// Wine runtime.
public enum InstallAction: Sendable, Equatable {
    case download(url: String, fileName: String, extractArchive: Bool)
    case setWindowsVersion(String)
    case run(
        command: String,
        arguments: [String],
        workingDirectory: String?,
        isInstaller: Bool,
        environment: [String: String]
    )
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
            return .run(
                command: command,
                arguments: arguments,
                workingDirectory: step.workingDirectory,
                isInstaller: true,
                environment: step.environment
            )

        case .runCommand:
            guard let command = nonEmpty(step.command) else {
                return .skip(reason: "runCommand step has no command")
            }
            let arguments = step.arguments.isEmpty ? step.silentArguments : step.arguments
            return .run(
                command: command,
                arguments: arguments,
                workingDirectory: step.workingDirectory,
                isInstaller: false,
                environment: step.environment
            )

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
        var components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        let generic: Set<String> = ["download", "downloads", "dl", "get", "redirect"]
        while let last = components.last, generic.contains(last.lowercased()) {
            components.removeLast()
        }
        var base = components.last ?? url.lastPathComponent
        base = base.removingPercentEncoding ?? base
        return base.isEmpty ? nil : base
    }

    public static func isZip(_ fileName: String) -> Bool {
        fileName.lowercased().hasSuffix(".zip")
    }

    /// Installer exit codes that still mean "installed". Windows installers
    /// commonly return 3010 (reboot required) or 1641 (reboot initiated).
    public static func isSuccessfulInstallerStatus(_ status: Int32) -> Bool {
        status == 0 || status == 3010 || status == 1641
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    /// Split a command-line fragment on whitespace while honouring quotes, so
    /// `"/D=C:\Program Files\App"` stays one argument. Empty quoted arguments
    /// are preserved.
    public static func splitCommandLine(_ value: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var hasToken = false

        for character in value {
            if let active = quote {
                if character == active {
                    quote = nil
                } else {
                    current.append(character)
                }
                hasToken = true
            } else if character == "\"" {
                quote = character
                hasToken = true
            } else if character.isWhitespace {
                if hasToken {
                    result.append(current)
                    current = ""
                    hasToken = false
                }
            } else {
                current.append(character)
                hasToken = true
            }
        }
        if hasToken { result.append(current) }
        return result
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
            "username": userName,
            "appdata": "\(user)\\AppData\\Roaming",
            "localappdata": "\(user)\\AppData\\Local",
            "temp": "\(user)\\AppData\\Local\\Temp",
            "tmp": "\(user)\\AppData\\Local\\Temp",
            "public": "C:\\users\\Public",
            "desktop": "\(user)\\Desktop",
            "startmenu": "\(user)\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu",
            "startmenu\\programs": "\(user)\\AppData\\Roaming\\Microsoft\\Windows\\Start Menu\\Programs",
            "favorites": "\(user)\\Favorites",
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
    ///
    /// UNC shares and drive mappings that point outside the bottle are never
    /// followed: they resolve to an inert path under `drive_c/.cork-unmapped`
    /// so a recipe cannot read or write arbitrary host files.
    public static func resolveWindowsPath(
        _ path: String,
        driveC: URL,
        environment: [String: String]
    ) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        guard !value.isEmpty else { return driveC.standardizedFileURL.path }

        if isUNCPath(value) {
            return unresolvedPath(value, driveC: driveC, kind: "unc")
        }

        value = expandEnvironment(value, environment: environment)
        if isUNCPath(value) {
            return unresolvedPath(value, driveC: driveC, kind: "unc")
        }

        value = value.replacingOccurrences(of: "\\", with: "/")

        if value.hasPrefix("~") {
            return (value as NSString).expandingTildeInPath
        }
        if value.hasPrefix("/") {
            // Native unix paths are deliberate (a recipe may reference a file
            // Cork itself downloaded), so they pass through unchanged.
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
                let bottleRoot = driveC.deletingLastPathComponent().standardizedFileURL
                let device = driveC.deletingLastPathComponent()
                    .appendingPathComponent("dosdevices", isDirectory: true)
                    .appendingPathComponent("\(letter):", isDirectory: true)
                guard FileManager.default.fileExists(atPath: device.path) else {
                    return unresolvedPath(value, driveC: driveC, kind: "drive-\(letter)")
                }
                let resolved = device.resolvingSymlinksInPath().standardizedFileURL
                guard isContained(resolved.path, in: bottleRoot) else {
                    return unresolvedPath(value, driveC: driveC, kind: "drive-\(letter)")
                }
                base = resolved
            }

            let candidate = trimmed.isEmpty
                ? base.standardizedFileURL
                : base.appendingPathComponent(trimmed).standardizedFileURL
            guard isContained(candidate.path, in: base) else {
                return unresolvedPath(value, driveC: driveC, kind: "drive-\(letter)")
            }
            return candidate.path
        }

        guard !value.isEmpty else { return driveC.standardizedFileURL.path }
        let candidate = driveC.appendingPathComponent(value).standardizedFileURL
        guard isContained(candidate.path, in: driveC) else {
            return unresolvedPath(value, driveC: driveC, kind: "relative")
        }
        return candidate.path
    }

    /// True for `\\server\share` and `//server/share` paths.
    static func isUNCPath(_ value: String) -> Bool {
        value.hasPrefix("\\\\") || value.hasPrefix("//")
    }

    private static func isContained(_ path: String, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(rootPath + "/")
    }

    /// A harmless, bottle-local destination for paths Cork refuses to map.
    /// Components are sanitised so nothing can traverse out of `drive_c`.
    private static func unresolvedPath(_ raw: String, driveC: URL, kind: String) -> String {
        let root = driveC
            .appendingPathComponent(".cork-unmapped", isDirectory: true)
            .appendingPathComponent(kind, isDirectory: true)
        let parts = raw
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { component -> String in
                let text = String(component)
                if text == "." || text == ".." { return "_" }
                return text.replacingOccurrences(of: ":", with: "_")
            }
        return parts.reduce(root) { $0.appendingPathComponent($1) }.standardizedFileURL.path
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
        // `<installerglob>`/`<localinstallerglob>` are globs (e.g. `7z92*.exe`),
        // not literal names: resolve them against what was actually downloaded.
        if isGlob(trimmed) {
            let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
            if let match = firstGlobMatch(pattern: normalized, root: cache) { return match }
            if let match = firstGlobMatch(pattern: normalized, root: driveC) { return match }
        }
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
        if isGlob(command) {
            let normalized = command.replacingOccurrences(of: "\\", with: "/")
            return firstGlobMatch(pattern: normalized, root: cache) != nil
                || firstGlobMatch(pattern: normalized, root: driveC) != nil
        }
        if command.contains("/") || command.contains("\\") || command.hasPrefix("%") || command.hasPrefix("~") {
            return true
        }
        let resolved = resolveLocalPath(command, driveC: driveC, cache: cache, environment: environment)
        return FileManager.default.fileExists(atPath: resolved)
    }

    /// Whether `value` is a shell-style glob (`*`/`?`) rather than a literal path.
    public static func isGlob(_ value: String) -> Bool {
        value.contains("*") || value.contains("?")
    }

    /// The first regular file under `root` whose path relative to `root` (or
    /// base name, for patterns without a directory component) matches `pattern`.
    /// Matching is case-insensitive, as Windows file names are.
    static func firstGlobMatch(pattern: String, root: URL) -> String? {
        let normalized = pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        let base = (normalized as NSString).lastPathComponent
        let rootPath = root.standardizedFileURL.path
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return nil
        }
        for case let url as URL in enumerator {
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isFile else { continue }
            let full = url.standardizedFileURL.path
            let relative = full.hasPrefix(rootPath + "/") ? String(full.dropFirst(rootPath.count + 1)) : url.lastPathComponent
            if globMatches(normalized, relative) || globMatches(base, url.lastPathComponent) {
                return full
            }
        }
        return nil
    }

    /// Case-insensitive shell glob match supporting `*` and `?`.
    static func globMatches(_ pattern: String, _ name: String) -> Bool {
        var regex = "^"
        for character in pattern {
            switch character {
            case "*": regex += ".*"
            case "?": regex += "."
            default: regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func expandEnvironment(_ value: String, environment: [String: String]) -> String {
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
