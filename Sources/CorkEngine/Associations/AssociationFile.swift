import CorkKit
import Foundation

/// The on-disk envelope for a bottle's file associations.
///
/// Cork owns this file (`cork-associations.json` inside the bottle directory);
/// it is the authoritative record independently of whether the Wine registry
/// could be updated. The schema version lets future Cork versions migrate the
/// file without guessing at its shape.
struct AssociationFile: Codable, Sendable {
    var schemaVersion: Int
    var entries: [AssociationEntry]

    init(schemaVersion: Int = AssociationFile.currentSchema, entries: [AssociationEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    static let currentSchema = 1
}

extension AssociationEntry {
    /// Canonicalises an extension: trims whitespace, lowercases and ensures a
    /// single leading dot. Windows treats extensions case-insensitively and
    /// Cork keys associations by the lowercased, dotted form.
    static func normalizeExtension(_ raw: String) -> String {
        var ext = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while ext.hasPrefix(".") {
            ext.removeFirst()
        }
        guard !ext.isEmpty else { return "" }
        return "." + ext
    }

    /// The extension without its leading dot, as used by `CFBundleTypeExtensions`.
    var extensionTag: String {
        var ext = fileExtension
        while ext.hasPrefix(".") {
            ext.removeFirst()
        }
        return ext
    }
}

extension Array where Element == AssociationEntry {
    /// Returns the entries with canonical extensions, de-duplicated by
    /// extension (last write wins) and sorted for stable, idempotent output.
    func normalizedAssociations() -> [AssociationEntry] {
        var byExtension: [String: AssociationEntry] = [:]
        for entry in self {
            let ext = AssociationEntry.normalizeExtension(entry.fileExtension)
            guard !ext.isEmpty else { continue }
            var cleaned = entry
            cleaned.fileExtension = ext
            byExtension[ext] = cleaned
        }
        return byExtension.values.sorted {
            $0.fileExtension.localizedCaseInsensitiveCompare($1.fileExtension) == .orderedAscending
        }
    }
}
