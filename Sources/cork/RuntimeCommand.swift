import ArgumentParser
import CorkKit

struct RuntimeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "runtime",
        abstract: "Download, verify and manage the Wine runtime.",
        subcommands: [Install.self, Status.self, Verify.self, Uninstall.self, Files.self, Wine.self]
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

    struct Wine: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "wine",
            abstract: "List, install and select Wine versions.",
            subcommands: [List.self, Install.self, Select.self, Clear.self]
        )

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "List available Wine versions and their install state."
            )

            func run() throws {
                let manager = try RuntimeManager()
                let selected = manager.selectedWineVersion
                let defaultVersion = manager.defaultWineVersion
                let wineComponents = manager.manifest.wineComponents

                print(Terminal.bold("Wine versions"))
                if wineComponents.isEmpty {
                    print(Terminal.warn("The runtime manifest lists no Wine components."))
                    return
                }
                print("  \("VERSION".padded(12)) \("ID".padded(14)) \("STATE".padded(12)) FLAGS")
                for component in wineComponents {
                    let installed = manager.isWineInstalled(version: component.version)
                    let state = installed
                        ? Terminal.green("installed".padded(12))
                        : Terminal.dim("missing".padded(12))
                    var flags: [String] = []
                    if component.version == defaultVersion { flags.append("default") }
                    if component.version == selected { flags.append("selected") }
                    let flagsText = flags.isEmpty ? "" : Terminal.dim(flags.joined(separator: ", "))
                    print("  \(component.version.padded(12)) \(component.id.padded(14)) \(state) \(flagsText)")
                }
                print("")
                let installedCount = manager.installedWineVersions().count
                if installedCount == 0 {
                    print(Terminal.warn("No Wine versions installed. Install one with: cork runtime wine install <version>"))
                } else if selected == nil {
                    print(Terminal.check("\(installedCount) Wine version(s) installed. Using the default."))
                } else if let selected {
                    print(Terminal.check("\(installedCount) Wine version(s) installed. Using Wine \(selected)."))
                }
            }
        }

        struct Install: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Download and install a specific Wine version."
            )

            @Argument(help: "Wine version to install (see: cork runtime wine list).")
            var version: String

            @Flag(name: .long, help: "Reinstall the version even if it is already present.")
            var force = false

            func run() async throws {
                let manager = try RuntimeManager()
                guard manager.manifest.wineComponent(forVersion: version) != nil else {
                    throw ValidationError("Unknown Wine version '\(version)'. Run 'cork runtime wine list' to see the options.")
                }

                let progress = ProgressLine()
                try await manager.installWine(version: version, force: force) { event in
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
                print(Terminal.bold("Wine \(version) ready."))
            }
        }

        struct Select: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Select an installed Wine version as the active default."
            )

            @Argument(help: "Wine version to use (must already be installed).")
            var version: String

            func run() throws {
                let manager = try RuntimeManager()
                try manager.selectWineVersion(version)
                let canonical = manager.manifest.wineComponent(forVersion: version)?.version ?? version
                print(Terminal.check("Selected Wine \(canonical)."))
            }
        }

        struct Clear: ParsableCommand {
            static let configuration = CommandConfiguration(
                abstract: "Clear the Wine selection and fall back to the manifest default."
            )

            func run() throws {
                let manager = try RuntimeManager()
                try manager.clearWineSelection()
                let fallback = manager.defaultWineVersion.map { "Wine \($0)" } ?? "the manifest default"
                print(Terminal.check("Cleared Wine selection. Using \(fallback)."))
            }
        }
    }
}
