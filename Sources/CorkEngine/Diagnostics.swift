import CorkKit
import Foundation

/// The outcome of one diagnostic check.
public enum DiagnosticStatus: String, Sendable, Hashable, Codable {
    case pass
    case warn
    case fail
    case skipped
}

public extension DiagnosticStatus {
    /// Single-character indicator used by the CLI (and asserted by tests).
    var symbol: String {
        switch self {
        case .pass: return "✓"
        case .warn: return "!"
        case .fail: return "✗"
        case .skipped: return "–"
        }
    }

    /// `true` only for checks that should fail the process exit code.
    var isFailure: Bool { self == .fail }
}

/// A single diagnostic finding.
///
/// NOTE: frozen CorkEngine API surface.
public struct DiagnosticCheck: Sendable, Hashable, Codable {
    public var id: String
    public var title: String
    public var status: DiagnosticStatus
    public var detail: String?

    public init(id: String, title: String, status: DiagnosticStatus, detail: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
    }
}

/// The result of a full diagnostic run (CrossOver's `cxdiag` equivalent).
public struct DiagnosticReport: Sendable, Hashable, Codable {
    public var checks: [DiagnosticCheck]
    public var bottle: String?

    public init(checks: [DiagnosticCheck], bottle: String? = nil) {
        self.checks = checks
        self.bottle = bottle
    }

    public var hasFailures: Bool { checks.contains { $0.status == .fail } }
}

public extension DiagnosticReport {
    /// The first check with the given id, if any. Handy for callers and tests.
    func check(id: String) -> DiagnosticCheck? { checks.first { $0.id == id } }

    /// Checks that would fail the process exit code.
    var failures: [DiagnosticCheck] { checks.filter { $0.status == .fail } }

    /// Checks that need attention but are not fatal.
    var warnings: [DiagnosticCheck] { checks.filter { $0.status == .warn } }
}

/// Environment/bottle diagnostics (CrossOver's `cxdiag` equivalent).
public struct Diagnostics: Sendable {
    public let paths: CorkPaths

    public init(paths: CorkPaths = .resolve()) {
        self.paths = paths
    }

    /// Run every applicable check. `bottle`, when supplied, adds per-bottle
    /// checks. This never throws for a missing bottle (that is reported as a
    /// `fail` check); the `throws` signature is part of the frozen API.
    public func run(bottle: String? = nil) throws -> DiagnosticReport {
        var checks: [DiagnosticCheck] = []
        checks.append(contentsOf: HostChecks.checks())
        checks.append(contentsOf: RuntimeChecks.checks(paths: paths))
        if let bottle, !bottle.isEmpty {
            checks.append(contentsOf: BottleChecks.checks(named: bottle, paths: paths))
        }
        return DiagnosticReport(checks: checks, bottle: bottle)
    }
}

public extension Diagnostics {
    /// Host CPU architecture as reported by `uname(2).machine`
    /// (`"arm64"`, `"x86_64"`, …). Returns `"unknown"` if it cannot be read.
    static func hostArchitecture() -> String {
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

/// Reads CrossOver's `cxfixes.xml` *when the user supplies one* (never bundled).
///
/// ## Schema notes (observed 2026-10 on CrossOver's shipped `cxfixes.xml`)
///
/// The file is a **host-system** fix catalog, not an application database. Its
/// shape is:
///
/// ```xml
/// <cxfixes release="…">
///   <distributions>…</distributions>
///   <cxproducts>…</cxproducts>
///   <fixes>
///     <fix id="pygi" title="…" description="…">
///       <cx id="cx19" level="required"/>
///       <fixfor distribution="arch"><package name="python-gobject"/></fixfor>
///     </fix>
///     …
///   </fixes>
/// </cxfixes>
/// ```
///
/// There is **no per-application association** in the real file, so ``fixes(appID:)``
/// is keyed by the `<fix>`'s stable `id` (falling back to its `title`). Each
/// value is the human-readable description, falling back to the title. Files
/// whose schema cannot be recognised yield an empty map and never throw.
public struct CxFixes: Sendable {
    public let fileURL: URL
    private let fixesByApp: [String: [String]]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.fixesByApp = try CxFixesParser.parse(fileURL: fileURL)
    }

    public var fixCount: Int { fixesByApp.values.reduce(0) { $0 + $1.count } }

    public func fixes(appID: String) -> [String] { fixesByApp[appID] ?? [] }

    /// Every fix key, sorted, for display/debugging.
    public var fixIDs: [String] { fixesByApp.keys.sorted() }
}

public enum CxFixesParser {
    /// Best-effort parse of a user-supplied `cxfixes.xml`.
    ///
    /// Never throws for malformed or unrecognised data: an unreadable file, a
    /// non-`cxfixes` root, or a file with no `<fix>` records all return `[:]`.
    public static func parse(fileURL: URL) throws -> [String: [String]] {
        CxFixesSAX.parse(fileURL: fileURL)
    }
}
