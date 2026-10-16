import CorkKit
import Foundation

/// The outcome of one diagnostic check.
public enum DiagnosticStatus: String, Sendable, Hashable, Codable {
    case pass
    case warn
    case fail
    case skipped
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

/// Environment/bottle diagnostics.
///
/// TODO(diag): implement checks (arch, Rosetta, runtime integrity, bottles,
/// graphics backend, disk, screen, Java/GPU) for a bottle or the system.
public struct Diagnostics: Sendable {
    public let paths: CorkPaths

    public init(paths: CorkPaths = .resolve()) {
        self.paths = paths
    }

    public func run(bottle: String? = nil) throws -> DiagnosticReport {
        _ = bottle
        return DiagnosticReport(checks: [], bottle: bottle)
    }
}

/// Reads CrossOver's `cxfixes.xml` *when the user supplies one* (never bundled).
///
/// TODO(diag): parse version-specific fixes, or return an empty list.
public struct CxFixes: Sendable {
    public let fileURL: URL
    private let fixesByApp: [String: [String]]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.fixesByApp = try CxFixesParser.parse(fileURL: fileURL)
    }

    public var fixCount: Int { fixesByApp.values.reduce(0) { $0 + $1.count } }

    public func fixes(appID: String) -> [String] { fixesByApp[appID] ?? [] }
}

public enum CxFixesParser {
    public static func parse(fileURL: URL) throws -> [String: [String]] {
        _ = fileURL
        return [:]
    }
}
