import Foundation

/// Merges a bottle's file associations into a macOS bundle's `Info.plist`.
///
/// Each association becomes a `CFBundleDocumentTypes` entry (extension → ProgID
/// command) plus a `UTExportedTypeDeclarations` entry per ProgID, so Finder and
/// Launch Services advertise the generated `.app` for those file types.
enum BundleDocumentTypes {
    /// UTI namespace Cork owns for generated bundles.
    static let utiPrefix = "tools.cork.assoc"

    struct MergeResult {
        var plist: [String: Any]
        /// Registered extensions, with dot, sorted and de-duplicated.
        var extensions: [String]
    }

    static func applying(_ entries: [AssociationEntry], to plist: [String: Any]) -> MergeResult {
        let normalized = entries.normalizedAssociations()
        guard !normalized.isEmpty else {
            return MergeResult(plist: plist, extensions: [])
        }

        let utiByProgID = Dictionary(
            uniqueKeysWithValues: normalized.map { ($0.progID, uti(for: $0.progID)) }
        )
        let registered = normalized.map(\.fileExtension)
        let registeredTags = Set(normalized.map(\.extensionTag))

        var documentTypes = (plist["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []
        documentTypes.removeAll { existing in
            let tags = (existing["CFBundleTypeExtensions"] as? [String]) ?? []
            return !registeredTags.isDisjoint(with: tags.map { $0.lowercased() })
        }
        for entry in normalized {
            documentTypes.append([
                "CFBundleTypeExtensions": [entry.extensionTag],
                "CFBundleTypeName": entry.friendlyName ?? entry.progID,
                "CFBundleTypeRole": "Editor",
                "LSItemContentTypes": [utiByProgID[entry.progID] ?? uti(for: entry.progID)],
            ])
        }

        var typeDeclarations = (plist["UTExportedTypeDeclarations"] as? [[String: Any]]) ?? []
        let ourIdentifiers = Set(utiByProgID.values)
        typeDeclarations.removeAll { existing in
            guard let identifier = existing["UTTypeIdentifier"] as? String else { return false }
            return ourIdentifiers.contains(identifier)
        }
        // One declaration per ProgID, listing every extension mapped to it.
        var extensionsByProgID: [String: [String]] = [:]
        for entry in normalized {
            extensionsByProgID[entry.progID, default: []].append(entry.extensionTag)
        }
        for progID in utiByProgID.keys.sorted() {
            let sample = normalized.first { $0.progID == progID }
            typeDeclarations.append([
                "UTTypeIdentifier": utiByProgID[progID] ?? uti(for: progID),
                "UTTypeDescription": sample?.friendlyName ?? progID,
                "UTTypeConformsTo": ["public.data"],
                "UTTypeTagSpecification": [
                    "public.filename-extension": (extensionsByProgID[progID] ?? []).sorted()
                ],
            ])
        }

        var merged = plist
        merged["CFBundleDocumentTypes"] = documentTypes
        merged["UTExportedTypeDeclarations"] = typeDeclarations
        return MergeResult(
            plist: merged,
            extensions: Array(Set(registered)).sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }
        )
    }

    static func uti(for progID: String) -> String {
        "\(utiPrefix).\(slug(progID))"
    }

    /// Lowercase, dash-separated slug suitable for a UTI/identifier.
    private static func slug(_ text: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let parts = text.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
        let slug = parts.joined(separator: "-")
        return slug.isEmpty ? "type" : slug
    }
}
