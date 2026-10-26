import CorkKit
import Foundation

/// Resolves the `executable` argument of `AppBundler.createBundle` into a Unix
/// path that the `cork run` CLI (and therefore Wine) can open directly.
///
/// Cork's `run` command expects a Unix path (it calls `fileExists`). When the
/// caller supplies a Windows path such as `C:\Program Files\App\app.exe` we map
/// it into the bottle's prefix (`drive_c`) so the produced bundle works without
/// the user having to translate paths by hand.
enum WindowsPathResolver {
    /// Returns the Unix path for `executable`, using `bottle` for drive mapping.
    static func resolve(_ executable: String, in bottle: Bottle) -> String {
        let trimmed = executable.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return trimmed }

        // Already Unix.
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        // `~/...` home-relative.
        if trimmed.hasPrefix("~") {
            return (trimmed as NSString).expandingTildeInPath
        }

        // Windows drive path: `C:\dir\file.exe` or `C:/dir/file.exe`.
        if let match = driveMatch(trimmed) {
            let drive = match.drive.lowercased()
            let rest = match.rest.replacingOccurrences(of: "\\", with: "/")
            return driveRoot(for: drive, in: bottle)
                .appendingPathComponent(rest)
                .path
        }

        return trimmed
    }

    private struct DriveMatch {
        let drive: String
        let rest: String
    }

    /// Matches `X:\...` / `X:/...` and captures the drive letter and remainder.
    private static func driveMatch(_ path: String) -> DriveMatch? {
        guard path.count >= 3 else { return nil }
        let characters = Array(path)
        guard characters[0].isLetter, characters[1] == ":" else { return nil }
        guard characters[2] == "\\" || characters[2] == "/" else { return nil }
        let rest = String(characters.dropFirst(3))
        return DriveMatch(drive: String(characters[0]), rest: rest)
    }

    /// The Unix directory backing a Windows drive letter. `C:` maps to the
    /// bottle's `drive_c`; other letters are looked up under `dosdevices/`
    /// (a symlink Wine creates) and fall back to `drive_c`.
    private static func driveRoot(for drive: String, in bottle: Bottle) -> URL {
        let defaultRoot = bottle.driveCDirectory
        guard drive != "c" else { return defaultRoot }

        let dosDevice = bottle.url
            .appendingPathComponent("dosdevices", isDirectory: true)
            .appendingPathComponent("\(drive):", isDirectory: false)
        // `resolvingSymlinksInPath` follows Wine's `c:` -> `../drive_c` links.
        let resolved = dosDevice.resolvingSymlinksInPath()
        if FileManager.default.fileExists(atPath: resolved.path) {
            return resolved
        }
        return defaultRoot
    }
}
