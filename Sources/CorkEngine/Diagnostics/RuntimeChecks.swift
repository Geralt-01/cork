import CorkKit
import Foundation

/// Runtime checks: whether a Wine runtime is installed and whether each
/// manifest component passes ``RuntimeManager/verify()``.
enum RuntimeChecks {
    static func checks(paths: CorkPaths) -> [DiagnosticCheck] {
        var checks: [DiagnosticCheck] = []

        let manager: RuntimeManager
        do {
            manager = try RuntimeManager(paths: paths)
        } catch {
            checks.append(
                DiagnosticCheck(
                    id: "runtime.manifest",
                    title: "Runtime manifest",
                    status: .fail,
                    detail: describe(error)
                )
            )
            return checks
        }

        checks.append(wineInstalled(manager))

        let required = requiredComponentIDs(paths: paths)
        for result in manager.verify() {
            // The wine component is covered by `runtime.wine` above.
            if manager.manifest.component(id: result.id)?.kind == .wine { continue }
            checks.append(component(result, required: required.contains(result.id)))
        }
        return checks
    }

    private static func wineInstalled(_ manager: RuntimeManager) -> DiagnosticCheck {
        guard manager.isWineReady else {
            return DiagnosticCheck(
                id: "runtime.wine",
                title: "Wine runtime",
                status: .fail,
                detail: "not installed — run 'cork runtime install'"
            )
        }
        let version = (try? manager.requireWine().version()) ?? "unknown"
        return DiagnosticCheck(id: "runtime.wine", title: "Wine runtime", status: .pass, detail: version)
    }

    private static func component(
        _ result: RuntimeManager.VerificationResult,
        required: Bool
    ) -> DiagnosticCheck {
        let status: DiagnosticStatus
        let detail: String
        if result.installed {
            status = .pass
            detail = result.detail
        } else if result.detail == "not installed" {
            if required {
                status = .fail
                detail = "required by a bottle but not installed — run 'cork runtime install \(result.id)'"
            } else {
                status = .warn
                detail = "not installed"
            }
        } else {
            status = .fail
            detail = result.detail
        }
        return DiagnosticCheck(
            id: "runtime.component.\(result.id)",
            title: "Runtime component \(result.id) (\(result.version))",
            status: status,
            detail: detail
        )
    }

    /// Graphics components that at least one configured bottle depends on.
    static func requiredComponentIDs(paths: CorkPaths) -> Set<String> {
        let listing = (try? BottleManager(paths: paths))?.listWithIssues() ?? BottleListing()
        return Set(listing.bottles.compactMap { $0.settings.backend.requiresComponentID })
    }

    private static func describe(_ error: Error) -> String {
        if let corkError = error as? CorkError {
            return corkError.errorDescription ?? "\(corkError)"
        }
        return "\(error)"
    }
}
