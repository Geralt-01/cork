import CorkKit
import Foundation

/// Per-bottle checks: existence, prefix validity, graphics files, Windows version.
enum BottleChecks {
    static func checks(named name: String, paths: CorkPaths) -> [DiagnosticCheck] {
        let directory = paths.bottleDirectory(named: name)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return missingChecks(
                name: name,
                detail: "not found at \(directory.path) — run 'cork bottle create \(name)'"
            )
        }

        let bottle: Bottle
        do {
            bottle = try Bottle.load(at: directory)
        } catch {
            return missingChecks(name: name, detail: "unreadable: \(describe(error))")
        }

        return [
            DiagnosticCheck(id: "bottle.exists", title: "Bottle '\(name)'", status: .pass, detail: directory.path),
            prefix(bottle),
            graphics(bottle),
            windowsVersion(bottle),
        ]
    }

    private static func missingChecks(name: String, detail: String) -> [DiagnosticCheck] {
        [
            DiagnosticCheck(id: "bottle.exists", title: "Bottle '\(name)'", status: .fail, detail: detail),
            DiagnosticCheck(id: "bottle.prefix", title: "Windows prefix", status: .skipped, detail: "bottle missing"),
            DiagnosticCheck(id: "bottle.graphics", title: "Graphics backend", status: .skipped, detail: "bottle missing"),
            DiagnosticCheck(id: "bottle.windows", title: "Windows version", status: .skipped, detail: "bottle missing"),
        ]
    }

    static func prefix(_ bottle: Bottle) -> DiagnosticCheck {
        let driveC = bottle.driveCDirectory
        if FileManager.default.fileExists(atPath: driveC.path) {
            return DiagnosticCheck(id: "bottle.prefix", title: "Windows prefix", status: .pass, detail: "drive_c present")
        }
        return DiagnosticCheck(
            id: "bottle.prefix",
            title: "Windows prefix",
            status: .fail,
            detail: "missing drive_c (incomplete prefix)"
        )
    }

    static func graphics(_ bottle: Bottle) -> DiagnosticCheck {
        let backend = bottle.settings.backend
        if backend == .wined3d {
            return DiagnosticCheck(
                id: "bottle.graphics",
                title: "Graphics backend",
                status: .pass,
                detail: "\(backend.displayName) (no extra files required)"
            )
        }

        let files = bottle.metadata.graphicsFiles
        guard !files.isEmpty else {
            return DiagnosticCheck(
                id: "bottle.graphics",
                title: "Graphics backend",
                status: .warn,
                detail: "\(backend.displayName): no files recorded"
            )
        }

        let missing = files.filter {
            !FileManager.default.fileExists(atPath: bottle.url.appendingPathComponent($0).path)
        }
        if missing.isEmpty {
            return DiagnosticCheck(
                id: "bottle.graphics",
                title: "Graphics backend",
                status: .pass,
                detail: "\(backend.displayName): \(files.count) file(s) present"
            )
        }
        return DiagnosticCheck(
            id: "bottle.graphics",
            title: "Graphics backend",
            status: .fail,
            detail: "\(backend.displayName): \(missing.count)/\(files.count) file(s) missing"
        )
    }

    static func windowsVersion(_ bottle: Bottle) -> DiagnosticCheck {
        let version = bottle.settings.windowsVersion
        return DiagnosticCheck(
            id: "bottle.windows",
            title: "Windows version",
            status: .pass,
            detail: "\(version.displayName) (\(version.rawValue))"
        )
    }

    private static func describe(_ error: Error) -> String {
        if let corkError = error as? CorkError {
            return corkError.errorDescription ?? "\(corkError)"
        }
        return "\(error)"
    }
}
