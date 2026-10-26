import Foundation

public extension Bottle {
    /// Resolve an executable path supplied on the command line or by a recipe.
    ///
    /// Accepted forms:
    /// * absolute Unix paths (`/Users/me/game.exe`),
    /// * `~`-relative paths (`~/Downloads/game.exe`),
    /// * Windows drive paths (`C:\Program Files\App\app.exe`, `C:/Games/a.exe`),
    /// * Windows paths with environment variables (`%ProgramFiles%\App\a.exe`),
    /// * bare file names, which are looked up in `drive_c` (e.g. `game.exe`).
    ///
    /// Existing Unix paths always win, so a file in the current directory is
    /// never shadowed by a same-named file inside the bottle.
    func resolveExecutablePath(_ raw: String) -> URL {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        guard !value.isEmpty else {
            return URL(fileURLWithPath: value)
        }

        // Unix absolute path or home-relative path.
        if value.hasPrefix("~") {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
                .standardizedFileURL
        }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value).standardizedFileURL
        }

        // A relative Unix path that actually exists (preserves the historical
        // behaviour of running `./game.exe`).
        let direct = URL(fileURLWithPath: value)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct.standardizedFileURL
        }

        if let mapped = windowsPathToUnix(value) {
            return URL(fileURLWithPath: mapped).standardizedFileURL
        }
        return direct.standardizedFileURL
    }

    /// Resolve a Windows path to a Unix path inside this bottle's prefix.
    ///
    /// Returns `nil` for paths Cork cannot map (UNC shares and empty strings).
    func windowsPathToUnix(_ raw: String) -> String? {
        let user = windowsUserName()
        let environment = windowsEnvironment(userName: user)
        var value = Self.expandEnvironment(raw, using: environment)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        guard !value.isEmpty else { return nil }

        // Backslashes are path separators on Windows; forward slashes work too.
        value = value.replacingOccurrences(of: "\\", with: "/")

        // UNC paths (`\\server\share`) live outside the prefix.
        if value.hasPrefix("//") || value.hasPrefix("\\\\") {
            return nil
        }

        let characters = Array(value)
        if characters.count >= 2, characters[0].isLetter, characters[1] == ":" {
            let drive = String(characters[0]).lowercased()
            var rest = String(characters.dropFirst(2))
            if rest.hasPrefix("/") { rest.removeFirst() }

            let base: URL
            if drive == "c" {
                base = driveCDirectory
            } else {
                let device = url
                    .appendingPathComponent("dosdevices", isDirectory: true)
                    .appendingPathComponent("\(drive):", isDirectory: false)
                    .resolvingSymlinksInPath()
                // Honour a configured drive mapping when it exists; otherwise
                // keep historical behaviour and resolve inside drive_c.
                base = FileManager.default.fileExists(atPath: device.path)
                    ? device
                    : driveCDirectory
            }

            if rest.isEmpty { return base.standardizedFileURL.path }
            return base.appendingPathComponent(rest).standardizedFileURL.path
        }

        // A bare file name or a relative Windows path is relative to drive_c.
        return driveCDirectory.appendingPathComponent(value).standardizedFileURL.path
    }

    /// Convert a Unix path to the Windows path Wine sees for it, using the
    /// bottle's drive mappings. Falls back to `Z:` (Wine's root drive), which
    /// exists in every default prefix.
    func windowsPath(forLocalPath raw: String) -> String {
        let fm = FileManager.default
        let local = URL(fileURLWithPath: raw).standardizedFileURL.path

        func windowsPath(letter: Character, root: String) -> String {
            let suffix: String
            if local == root {
                suffix = ""
            } else if local.hasPrefix(root + "/") {
                suffix = String(local.dropFirst(root.count + 1))
            } else if root == "/", local.hasPrefix("/") {
                suffix = String(local.dropFirst())
            } else {
                suffix = String(local.dropFirst())
            }
            let tail = suffix.replacingOccurrences(of: "/", with: "\\")
            let drive = String(letter).uppercased()
            return tail.isEmpty ? "\(drive):\\" : "\(drive):\\\(tail)"
        }

        let driveC = driveCDirectory.standardizedFileURL.path
        if local == driveC || local.hasPrefix(driveC + "/") {
            return windowsPath(letter: "C", root: driveC)
        }

        let dosdevices = url.appendingPathComponent("dosdevices", isDirectory: true)
        guard let entries = try? fm.contentsOfDirectory(
            at: dosdevices,
            includingPropertiesForKeys: nil
        ) else {
            return windowsPath(letter: "Z", root: "/")
        }

        var best: (letter: Character, root: String)?
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.count == 2, name.hasSuffix(":"), let letter = name.first else { continue }
            let target = entry.resolvingSymlinksInPath().standardizedFileURL.path
            let matches = local == target || (target == "/" ? local.hasPrefix("/") : local.hasPrefix(target + "/"))
            guard matches else { continue }
            if let current = best {
                if target.count > current.root.count { best = (letter, target) }
            } else {
                best = (letter, target)
            }
        }
        if let best {
            return windowsPath(letter: best.letter, root: best.root)
        }
        // Z: is Wine's mapping for the Unix root and is always present in a
        // default prefix; if it is missing the caller will surface an error.
        return windowsPath(letter: "Z", root: "/")
    }

    /// The Windows user name used for `%USERPROFILE%`-style expansion: the
    /// macOS user name when that profile exists in the prefix, else the first
    /// profile directory Wine created.
    func windowsUserName() -> String {
        let users = driveCDirectory.appendingPathComponent("users", isDirectory: true)
        let current = NSUserName()
        if FileManager.default.fileExists(atPath: users.appendingPathComponent(current).path) {
            return current
        }
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: users.path) {
            let candidates = entries.filter { !$0.hasPrefix(".") }.sorted()
            if let first = candidates.first { return first }
        }
        return current
    }

    /// Environment map for expanding `%VAR%` tokens in Windows paths.
    func windowsEnvironment(userName: String) -> [String: String] {
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
        ]
    }

    /// Expand `%NAME%` tokens case-insensitively, leaving unknown tokens intact.
    static func expandEnvironment(_ value: String, using environment: [String: String]) -> String {
        guard value.contains("%") else { return value }
        var lowered: [String: String] = [:]
        for (key, replacement) in environment {
            lowered[key.lowercased()] = replacement
        }

        let characters = Array(value)
        var output = ""
        var index = 0
        while index < characters.count {
            if characters[index] == "%" {
                var end = index + 1
                while end < characters.count && characters[end] != "%" { end += 1 }
                if end < characters.count {
                    let token = String(characters[(index + 1)..<end])
                    if let replacement = lowered[token.lowercased()] {
                        output += replacement
                    } else {
                        output += "%" + token + "%"
                    }
                    index = end + 1
                    continue
                }
            }
            output.append(characters[index])
            index += 1
        }
        return output
    }
}
