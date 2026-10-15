import ArgumentParser
import CorkKit
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that your Mac and Cork are ready."
    )

    func run() throws {
        print(Terminal.bold("Cork doctor"))
        print("")

        var problems = 0

        let architecture = currentArchitecture()
        print(Terminal.check("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"))
        print(Terminal.bullet("architecture: \(architecture)"))

        if architecture == "arm64" {
            let paths = CorkPaths.resolve()
            let manager = try RuntimeManager(paths: paths)
            if manager.isWineReady, let installation = try? manager.requireWine() {
                if installation.isRosettaAvailable() {
                    print(Terminal.check("Rosetta 2 is available (needed for x86_64 Wine)"))
                } else {
                    problems += 1
                    print(Terminal.cross("Rosetta 2 is not installed"))
                    print(Terminal.dim("  fix: softwareupdate --install-rosetta --agree-to-license"))
                }
            }
        }

        let paths = CorkPaths.resolve()
        print(Terminal.bullet("Cork home: \(paths.root.path)"))

        let manager = try RuntimeManager(paths: paths)
        if manager.isWineReady {
            let version = (try? manager.requireWine().version()) ?? "unknown"
            print(Terminal.check("Wine runtime installed (\(version))"))
        } else {
            problems += 1
            print(Terminal.cross("Wine runtime not installed"))
            print(Terminal.dim("  fix: cork runtime install"))
        }

        let listing = (try? BottleManager(paths: paths))?.listWithIssues() ?? BottleListing()
        let requiredComponentIDs = Set(listing.bottles.compactMap { $0.settings.backend.requiresComponentID })

        for result in manager.verify() where !result.installed {
            if result.detail == "not installed" {
                if requiredComponentIDs.contains(result.id) {
                    problems += 1
                    print(Terminal.cross("\(result.id): required by a bottle but not installed"))
                    print(Terminal.dim("  fix: cork runtime install \(result.id)"))
                }
            } else {
                problems += 1
                print(Terminal.warn("\(result.id): \(result.detail)"))
            }
        }

        if listing.issues.isEmpty {
            print(Terminal.check("\(listing.bottles.count) bottle(s) configured"))
        } else {
            print(Terminal.bullet("\(listing.bottles.count) bottle(s) configured"))
            for issue in listing.issues {
                problems += 1
                print(Terminal.warn("unreadable bottle '\(issue.directoryName)': \(issue.reason)"))
            }
        }

        print("")
        if problems == 0 {
            print(Terminal.green("Everything looks good."))
        } else {
            print(Terminal.yellow("\(problems) item(s) need attention."))
            throw ExitCode.failure
        }
    }

    private func currentArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return machine
    }
}
