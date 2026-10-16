import CorkKit
import Foundation

/// Translates file associations into the `wine reg add` invocations that make
/// Windows programs honour them.
///
/// This is the `cxassoc.conf` equivalent on the Wine side: a ProgID plus its
/// `shell\open\command`, and the per-extension mapping under
/// `HKCU\Software\Classes`. The command arrays returned here are exactly what
/// `BottleManager.exec(named:command:arguments:)` passes after `reg`, so the
/// same output can be printed for inspection without a runtime installed.
public enum AssociationRegistry {
    /// Registry hive root for per-user file associations.
    public static let classesRoot = #"HKCU\Software\Classes"#

    /// The full ordered list of `reg` argument vectors for one association.
    public static func commands(for entry: AssociationEntry) -> [[String]] {
        let key = "\(classesRoot)\\\(entry.progID)"
        var commands: [[String]] = []

        // Friendly name as the ProgID's default value.
        commands.append([
            "add", key,
            "/ve", "/t", "REG_SZ", "/d", entry.friendlyName ?? entry.progID, "/f",
        ])
        if let friendlyName = entry.friendlyName, !friendlyName.isEmpty {
            commands.append([
                "add", key,
                "/v", "FriendlyTypeName", "/t", "REG_SZ", "/d", friendlyName, "/f",
            ])
        }

        // The command that opens a document of this type: "<exe>" [args] "%1".
        commands.append([
            "add", key + #"\shell\open\command"#,
            "/ve", "/t", "REG_SZ", "/d", openCommand(for: entry), "/f",
        ])

        // Map the extension to the ProgID.
        commands.append([
            "add", "\(classesRoot)\\\(entry.fileExtension)",
            "/ve", "/t", "REG_SZ", "/d", entry.progID, "/f",
        ])
        return commands
    }

    /// All commands for a set of associations, in stable order.
    public static func commands(for entries: [AssociationEntry]) -> [[String]] {
        entries.flatMap(commands(for:))
    }

    /// The `shell\open\command` value: `"<exe>" arg… "%1"`.
    public static func openCommand(for entry: AssociationEntry) -> String {
        var parts = ["\"\(entry.executable)\""]
        parts.append(contentsOf: entry.arguments)
        parts.append("\"%1\"")
        return parts.joined(separator: " ")
    }

    /// A human-readable, copy-pasteable `wine reg …` line per command.
    public static func commandLines(for entry: AssociationEntry) -> [String] {
        commands(for: entry).map { arguments in
            (["wine", "reg"] + arguments.map(quoteIfNeeded)).joined(separator: " ")
        }
    }

    public static func commandLines(for entries: [AssociationEntry]) -> [String] {
        entries.flatMap(commandLines(for:))
    }

    private static func quoteIfNeeded(_ value: String) -> String {
        if value.contains(" ") || value.contains("\"") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return value
    }
}
