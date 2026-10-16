import ArgumentParser
import CorkKit
import Foundation

struct BottleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bottle",
        abstract: "Create and manage isolated Windows environments (bottles).",
        subcommands: [Create.self, List.self, Info.self, Delete.self, Set.self, Kill.self, Logs.self]
    )

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Create a new bottle and initialize its Windows prefix."
        )

        @Argument(help: "Name of the new bottle.")
        var name: String

        @Option(name: .long, help: "Graphics backend: wined3d, dxvk, or dxmt.")
        var backend: String?

        @Option(name: .long, help: "Reported Windows version (e.g. win10, win7, winxp, win2000, win98).")
        var windows: String?

        @Flag(name: .long, help: "Replace an existing bottle with the same name.")
        var force = false

        @Flag(name: .long, help: "Skip the confirmation prompt when replacing a bottle.")
        var yes = false

        @Flag(name: .shortAndLong, help: "Show verbose output from Wine.")
        var verbose = false

        func run() async throws {
            var settings = BottleSettings()
            if let backend {
                try settings.apply(key: BottleSettings.Key.backend.rawValue, value: backend)
            }
            if let windows {
                try settings.apply(key: BottleSettings.Key.windows.rawValue, value: windows)
            }

            let manager = try BottleManager()
            if force, manager.exists(named: name) {
                try Confirm.ask("Bottle '\(name)' exists. Replace it and delete all of its data?", yes: yes)
            }
            let progress = ProgressLine()
            let verbose = self.verbose

            let bottle = try await manager.create(
                named: name,
                settings: settings,
                force: force,
                onEvent: { event in
                    switch event {
                    case .bootstrappingPrefix:
                        progress.update("initializing Windows prefix (this can take a minute)…")
                    case .applyingWindowsVersion:
                        progress.finish()
                        print(Terminal.arrow("setting reported Windows version"))
                    case .installingGraphics(let backend):
                        print(Terminal.arrow("installing graphics backend: \(backend.displayName)"))
                    case .warning(let message):
                        progress.finish()
                        print(Terminal.warn(message))
                    case .created:
                        break
                    }
                },
                onLine: { line in
                    if verbose {
                        print(Terminal.dim("  wine: \(line)"))
                    }
                }
            )
            progress.finish()

            print(Terminal.check("Created bottle '\(bottle.name)'"))
            print(Terminal.dim("  location: \(bottle.url.path)"))
            print(Terminal.dim("  backend:  \(bottle.settings.backend.displayName)"))
            print(Terminal.dim("  windows:  \(bottle.settings.windowsVersion.displayName)"))
            print(Terminal.dim("  wine:     \(bottle.metadata.wineVersion)"))
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List bottles.")

        func run() throws {
            let manager = try BottleManager()
            let listing = manager.listWithIssues()
            for issue in listing.issues {
                print(Terminal.warn("unreadable bottle '\(issue.directoryName)': \(issue.reason)"))
            }
            guard !listing.bottles.isEmpty else {
                if listing.issues.isEmpty {
                    print(Terminal.dim("No bottles yet. Create one with: cork bottle create my-game"))
                }
                return
            }
            print(Terminal.bold("Bottles"))
            print("  \("NAME".padded(24)) \("WINDOWS".padded(12)) \("BACKEND".padded(16)) CREATED")
            for bottle in listing.bottles {
                let line = "  "
                    + bottle.name.truncated(24).padded(24) + " "
                    + bottle.settings.windowsVersion.displayName.padded(12) + " "
                    + bottle.settings.backend.displayName.padded(16) + " "
                    + Formatting.date(bottle.metadata.createdAt)
                print(line)
            }
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show details about a bottle.")

        @Argument(help: "Name of the bottle.") var name: String

        func run() throws {
            let manager = try BottleManager()
            let bottle = try manager.load(named: name)
            let settings = bottle.settings

            print(Terminal.bold(bottle.name))
            print("  location:        \(bottle.url.path)")
            print("  created:         \(Formatting.date(bottle.metadata.createdAt))")
            print("  wine version:    \(bottle.metadata.wineVersion)")
            print("  windows version: \(settings.windowsVersion.displayName) (\(settings.windowsVersion.registryVersion))")
            print("  backend:         \(settings.backend.displayName)")
            print("  msync/esync:     \(settings.msync ? "on" : "off") / \(settings.esync ? "on" : "off")")
            if settings.backend == .dxvk {
                print("  dxvk async:      \(settings.dxvkAsync ? "on" : "off")")
                print("  dxvk hud:        \(settings.dxvkHUD ?? "off")")
            }
            if settings.backend == .dxmt {
                print("  metal hud:       \(settings.metalHUD ? "on" : "off")")
            }
            print("  debug channels:  \(settings.debugChannels.isEmpty ? "off" : settings.debugChannels)")
            print("  graphics files:  \(bottle.metadata.graphicsFiles.count)")
            if let log = bottle.latestLogFile() {
                print("  last log:        \(log.path)")
            }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a bottle and its prefix.")

        @Argument(help: "Name of the bottle.") var name: String

        @Flag(name: .long, help: "Skip the confirmation prompt.")
        var yes = false

        func run() throws {
            let manager = try BottleManager()
            guard manager.exists(named: name) else {
                throw CorkError.bottleNotFound(name: name)
            }
            try Confirm.ask("Delete bottle '\(name)' and all of its data?", yes: yes)
            try manager.delete(named: name)
            print(Terminal.check("Deleted bottle '\(name)'"))
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Change a bottle setting.",
            discussion: "Keys: \(BottleSettings.Key.allCases.map(\.rawValue).joined(separator: ", "))."
        )

        @Argument(help: "Name of the bottle.") var name: String

        @Argument(help: "One or more key=value assignments, e.g. backend=dxmt windows=win10.")
        var assignments: [String]

        func run() throws {
            guard !assignments.isEmpty else {
                throw ValidationError("Provide at least one key=value assignment.")
            }
            let manager = try BottleManager()
            var bottle = try manager.load(named: name)
            for assignment in assignments {
                let parts = assignment.split(separator: "=", maxSplits: 1).map(String.init)
                guard parts.count == 2 else {
                    throw ValidationError("Expected key=value, got '\(assignment)'.")
                }
                bottle = try manager.setSetting(named: name, key: parts[0], value: parts[1])
            }
            print(Terminal.check("Updated bottle '\(name)'"))
            print(Terminal.dim("  backend: \(bottle.settings.backend.displayName)   windows: \(bottle.settings.windowsVersion.displayName)"))
        }
    }

    struct Kill: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop all Windows processes in a bottle.")

        @Argument(help: "Name of the bottle.") var name: String

        func run() throws {
            let manager = try BottleManager()
            _ = try manager.kill(named: name)
            print(Terminal.check("Stopped all processes in '\(name)'"))
        }
    }

    struct Logs: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show the most recent log for a bottle.")

        @Argument(help: "Name of the bottle.") var name: String

        @Option(name: .long, help: "Only print the path to the log file.")
        var pathOnly = false

        func run() throws {
            let manager = try BottleManager()
            let bottle = try manager.load(named: name)
            guard let log = bottle.latestLogFile() else {
                print(Terminal.dim("No logs for '\(name)' yet."))
                return
            }
            if pathOnly {
                print(log.path)
                return
            }
            print(Terminal.dim(log.path))
            let contents: String
            do {
                contents = try String(contentsOf: log, encoding: .utf8)
            } catch {
                throw CorkError.fileSystem(reason: "could not read log file \(log.path): \(error.localizedDescription)")
            }
            print(contents)
        }
    }

    enum Formatting {
        static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()

        static func date(_ date: Date) -> String {
            formatter.string(from: date)
        }
    }
}
