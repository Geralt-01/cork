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

        @Flag(name: .long, help: "Also print the Wine registry commands that are applied.")
        var registry: Bool = false

        func run() throws {
            let paths = try AssocCommand.requireBottle(bottle)
            let store = AssociationStore(paths: paths)
            let entries = try store.read(bottle: bottle)
            print(Terminal.bold("\(entries.count) associations in '\(bottle)'"))
            for entry in entries {
                let ext = entry.fileExtension.padding(toLength: 8, withPad: " ", startingAt: 0)
                print("  \(ext)\(entry.progID)  →  \(entry.executable)")
            }
            if registry, !entries.isEmpty {
                print(Terminal.dim("  registry commands:"))
                for line in AssociationRegistry.commandLines(for: entries) {
                    print("    \(line)")
                }
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
            let paths = try AssocCommand.requireBottle(bottle)
            let resolved = progID ?? Self.generatedProgID(executable: executable, fileExtension: ext)
            try AssociationStore(paths: paths).set(
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

        /// Builds a stable ProgID from the program name and extension, e.g.
        /// `CorkPhotoshopImage12Psd`. Handles both Unix and `C:\…` paths.
        static func generatedProgID(executable: String, fileExtension ext: String) -> String {
            let normalized = executable
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/")
            let base = (normalized as NSString).lastPathComponent
            let stem = (base as NSString).deletingPathExtension
            let allowed = CharacterSet.alphanumerics
            let name = stem.unicodeScalars
                .filter { allowed.contains($0) }
                .map(String.init)
                .joined()
            let suffix = ext.dropFirst()
            return "Cork\(name.isEmpty ? "App" : name)\(suffix)"
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
            let paths = try AssocCommand.requireBottle(bottle)
            try AssociationStore(paths: paths).remove(fileExtension: ext, bottle: bottle)
            print(Terminal.check("removed \(ext) from '\(bottle)'"))
        }
    }

    /// Association writes create the bottle directory as a side effect, so
    /// reject unknown bottles up front instead of leaving a phantom behind.
    private static func requireBottle(_ name: String) throws -> CorkPaths {
        try Bottle.validateName(name)
        let paths = CorkPaths.resolve()
        guard FileManager.default.fileExists(atPath: paths.bottleDirectory(named: name).path) else {
            throw CorkError.bottleNotFound(name: name)
        }
        return paths
    }
}
