import CorkKit
import Foundation

/// Host-level checks: CPU architecture, macOS version, Rosetta, free disk space.
enum HostChecks {
    static func checks() -> [DiagnosticCheck] {
        [cpu(), macOSVersion(), rosetta(), disk()]
    }

    static func cpu() -> DiagnosticCheck {
        let architecture = Diagnostics.hostArchitecture()
        let recognised = architecture == "arm64" || architecture == "x86_64"
        return DiagnosticCheck(
            id: "host.cpu",
            title: "CPU architecture",
            status: recognised ? .pass : .warn,
            detail: recognised ? architecture : "\(architecture) (unrecognised)"
        )
    }

    static func macOSVersion() -> DiagnosticCheck {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let described = ProcessInfo.processInfo.operatingSystemVersionString
        // Cork's deployment target is macOS 13.
        let supported = version.majorVersion >= 13
        return DiagnosticCheck(
            id: "host.macos",
            title: "macOS version",
            status: supported ? .pass : .warn,
            detail: supported ? described : "\(described) (Cork targets macOS 13+)"
        )
    }

    static func rosetta() -> DiagnosticCheck {
        guard Diagnostics.hostArchitecture() == "arm64" else {
            return DiagnosticCheck(
                id: "host.rosetta",
                title: "Rosetta 2",
                status: .skipped,
                detail: "not required on this CPU"
            )
        }
        let result = try? ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/arch"),
            arguments: ["-x86_64", "/usr/bin/true"]
        )
        let available = result?.succeeded ?? false
        return DiagnosticCheck(
            id: "host.rosetta",
            title: "Rosetta 2",
            status: available ? .pass : .fail,
            detail: available
                ? "available (needed for x86_64 Wine)"
                : "not installed — run 'softwareupdate --install-rosetta --agree-to-license'"
        )
    }

    static func disk() -> DiagnosticCheck {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else {
            return DiagnosticCheck(
                id: "host.disk",
                title: "Free disk space",
                status: .warn,
                detail: "unavailable"
            )
        }

        let gibibyte: Int64 = 1024 * 1024 * 1024
        let status: DiagnosticStatus
        if available < 1 * gibibyte {
            status = .fail
        } else if available < 5 * gibibyte {
            status = .warn
        } else {
            status = .pass
        }
        return DiagnosticCheck(
            id: "host.disk",
            title: "Free disk space (home volume)",
            status: status,
            detail: ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
        )
    }
}
