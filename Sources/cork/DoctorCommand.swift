import ArgumentParser
import CorkEngine
import CorkKit
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that your Mac and Cork are ready."
    )

    @Option(name: .long, help: "Include diagnostics for a specific bottle.")
    var bottle: String?

    func run() throws {
        print(Terminal.bold("Cork doctor"))
        print("")

        let paths = CorkPaths.resolve()
        let report = (try? Diagnostics(paths: paths).run(bottle: bottle))
            ?? DiagnosticReport(checks: [], bottle: bottle)

        for check in report.checks {
            print(line(for: check))
        }

        // CrossOver fixes are best-effort and only read from a user-supplied file.
        if let fixes = CxFixesDiscovery.load() {
            let noun = fixes.fixCount == 1 ? "entry" : "entries"
            print(Terminal.bullet("CrossOver fixes: \(fixes.fixCount) \(noun) (\(fixes.fileURL.lastPathComponent))"))
        }

        print("")
        let failures = report.failures.count
        let warnings = report.warnings.count
        if failures == 0 && warnings == 0 {
            print(Terminal.green("Everything looks good."))
        } else if failures == 0 {
            print(Terminal.yellow("\(warnings) warning(s); no failures."))
        } else {
            print(Terminal.yellow("\(failures) problem(s), \(warnings) warning(s)."))
            throw ExitCode.failure
        }
    }

    private func line(for check: DiagnosticCheck) -> String {
        var text = "\(colored(check.status)) \(check.title)"
        if let detail = check.detail, !detail.isEmpty {
            text += Terminal.dim(" — \(detail)")
        }
        return text
    }

    private func colored(_ status: DiagnosticStatus) -> String {
        switch status {
        case .pass: return Terminal.green(status.symbol)
        case .warn: return Terminal.yellow(status.symbol)
        case .fail: return Terminal.red(status.symbol)
        case .skipped: return Terminal.dim(status.symbol)
        }
    }
}
