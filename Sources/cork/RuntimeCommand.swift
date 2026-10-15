import ArgumentParser
import CorkKit

struct RuntimeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runtime",
        abstract: "Download, verify and manage the Wine runtime.",
        subcommands: [Install.self, Status.self, Verify.self, Uninstall.self, Files.self]
    )

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download and install runtime components (Wine, DXMT, DXVK)."
        )

        @Argument(help: "Component ids to install. Defaults to all components.")
        var components: [String] = []

        @Flag(name: .long, help: "Reinstall components even if they are already present.")
        var force = false

        func run() async throws {
            let manager = try RuntimeManager()
            let progress = ProgressLine()
            try await manager.install(
                componentIDs: components.isEmpty ? nil : components,
                force: force
            ) { event in
                switch event {
                case .alreadyInstalled(let id):
                    print(Terminal.check("\(id) already installed"))
                case .downloading(let id, let bytes):
                    progress.finish()
                    print(Terminal.arrow("downloading \(id) (\(Terminal.formatBytes(bytes)))"))
                case .verifying(let id):
                    progress.finish()
                    print(Terminal.arrow("verifying \(id)"))
                case .extracting(let id):
                    print(Terminal.arrow("extracting \(id)"))
                case .installed(let id, let location):
                    progress.finish()
                    print(Terminal.check("installed \(id) → \(location)"))
                }
            } onDownloadProgress: { id, update in
                let fraction = update.fraction.map { String(format: "%5.1f%%", $0 * 100) } ?? "     "
                progress.update("\(id)  \(fraction)  \(Terminal.formatBytes(update.receivedBytes))")
            }
            progress.finish()
            print(Terminal.bold("Runtime ready."))
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show installed runtime components.")

        func run() throws {
            let paths = CorkPaths.resolve()
            let manager = try RuntimeManager(paths: paths)
            let results = Dictionary(uniqueKeysWithValues: manager.verify().map { ($0.id, $0) })
            print(Terminal.bold("Cork runtime"))
            print(Terminal.dim("  home: \(paths.root.path)"))
            print("")
            print("  \("ID".padded(8)) \("VERSION".padded(10)) \("STATE".padded(12)) SIZE")
            for component in manager.manifest.components {
                let result = results[component.id]
                let label: String
                let state: String
                if result?.installed == true {
                    label = "installed"
                    state = Terminal.green(label.padded(12))
                } else if result?.detail == "not installed" || result == nil {
                    label = "missing"
                    state = Terminal.dim(label.padded(12))
                } else if result?.detail == "version mismatch" {
                    label = "outdated"
                    state = Terminal.yellow(label.padded(12))
                } else {
                    label = "incomplete"
                    state = Terminal.yellow(label.padded(12))
                }
                print("  \(component.id.padded(8)) \(component.version.padded(10)) \(state) \(Terminal.formatBytes(component.size))")
            }
            print("")
            let wineReady = manager.manifest.wineComponent.map { results[$0.id]?.installed == true } ?? false
            if wineReady {
                print(Terminal.check("Wine is ready. Create a bottle with: cork bottle create my-game"))
            } else {
                print(Terminal.warn("Wine is not installed. Run: cork runtime install"))
            }
        }
    }

    struct Verify: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Check that installed components match the pinned manifest.")

        @Flag(name: .long, help: "Exit with a non-zero status if anything is missing or out of date.")
        var strict = false

        func run() throws {
            let manager = try RuntimeManager()
            var allGood = true
            for result in manager.verify() {
                if result.installed {
                    print(Terminal.check("\(result.id) \(result.version): \(result.detail)"))
                } else {
                    allGood = false
                    print(Terminal.cross("\(result.id) \(result.version): \(result.detail)"))
                }
            }
            if strict && !allGood {
                throw ExitCode.failure
            }
        }
    }

    struct Uninstall: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove installed runtime components.")

        @Argument(help: "Component ids to remove.")
        var components: [String] = []

        @Flag(name: .long, help: "Remove all components.")
        var all = false

        @Flag(name: .long, help: "Skip the confirmation prompt.")
        var yes = false

        func run() throws {
            let manager = try RuntimeManager()
            let ids = all ? manager.manifest.components.map(\.id) : components
            guard !ids.isEmpty else {
                throw ValidationError("Specify component ids to remove, or pass --all.")
            }
            let summary = all
                ? "Remove ALL runtime components (\(ids.count))?"
                : "Remove runtime components: \(ids.joined(separator: ", "))?"
            try Confirm.ask(summary, yes: yes)
            try manager.uninstall(componentIDs: ids)
            for id in ids {
                print(Terminal.check("removed \(id)"))
            }
        }
    }

    struct Files: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Print the Cork home directory.")

        func run() throws {
            print(CorkPaths.resolve().root.path)
        }
    }
}
