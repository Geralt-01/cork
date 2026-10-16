import ArgumentParser
import CorkEngine
import CorkKit
import Foundation

/// Manage file-type associations for a bottle (extension → Windows program).
///
/// NOTE: the associations track owns this file and completes the implementation.
struct AssocCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assoc",
        abstract: "Manage file associations for a bottle (extension → Windows program).",
        subcommands: [List.self, Set.self, Remove.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List associations for a bottle.")

        @Argument(help: "Name of the bottle.")
        var bottle: String

        func run() throws {
            let entries = try AssociationStore().read(bottle: bottle)
            print(Terminal.bold("\(entries.count) associations in '\(bottle)'"))
            for entry in entries {
                let ext = entry.fileExtension.padding(toLength: 8, withPad: " ", startingAt: 0)
                print("  \(ext)\(entry.progID)  →  \(entry.executable)")
            }
        }
    }

    struct Set: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Associate a file extension with a program in a bottle."
        )

        @Argument(help: "Name of the bottle.")
        var bottle: String

        @Argument(help: "Extension, including the dot (e.g. .psd)")
        var fileExtension: String

        @Argument(help: "Windows path of the program (C:\\…)")
        var executable: String

        @Option(name: .long, help: "Windows ProgID (generated if omitted).")
        var progID: String?

        @Option(name: .long, help: "Friendly name shown to the user.")
        var name: String?

        func run() throws {
            var ext = fileExtension
            if !ext.hasPrefix(".") { ext = "." + ext }
            let base = URL(fileURLWithPath: executable).deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: " ", with: "")
            let resolved = progID ?? ("Cork" + base + String(ext.dropFirst()))
            try AssociationStore().set(
                AssociationEntry(
                    fileExtension: ext,
                    progID: resolved,
                    friendlyName: name,
                    executable: executable
                ),
                bottle: bottle
            )
            print(Terminal.check("\(ext) → \(executable) in '\(bottle)'"))
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove an association.")

        @Argument(help: "Name of the bottle.")
        var bottle: String

        @Argument(help: "Extension, including the dot (e.g. .psd)")
        var fileExtension: String

        func run() throws {
            var ext = fileExtension
            if !ext.hasPrefix(".") { ext = "." + ext }
            try AssociationStore().remove(fileExtension: ext, bottle: bottle)
            print(Terminal.check("removed \(ext) from '\(bottle)'"))
        }
    }
}
