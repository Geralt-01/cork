import Foundation

/// Where a resolved compatibility rating came from.
public enum CompatRatingSource: String, Sendable, Hashable {
    /// The CrossOver compatibility database (`compatdb-*.dat`), when it could
    /// be read.
    case compatDB = "compatdb"
    /// A recipe medal from a `crossover.tie` catalog.
    case recipe = "recipe"
}

/// A resolved rating plus its provenance.
public struct ResolvedCompatRating: Sendable, Hashable {
    public var entry: CompatEntry
    public var source: CompatRatingSource

    public init(entry: CompatEntry, source: CompatRatingSource) {
        self.entry = entry
        self.source = source
    }
}

/// Resolves an application's compatibility rating.
///
/// The CrossOver compatibility database is the preferred source, but its shipped
/// file is an undecodable obfuscated binary (see ``CompatDatabase``), so in
/// practice ratings come from the recipe medals in a CrossTie catalog. This
/// helper encapsulates that preference order so callers do not have to.
public enum CompatRating {
    /// Resolve the best rating for `appID`.
    ///
    /// Prefers the compatibility database, then falls back to the recipe
    /// catalog's medal/rating. Returns `nil` when neither source knows the app.
    public static func resolve(
        appID: String,
        catalog: AppCatalog?,
        compat: CompatDatabase?
    ) -> CompatEntry? {
        resolveDetailed(appID: appID, catalog: catalog, compat: compat)?.entry
    }

    /// Like ``resolve(appID:catalog:compat:)`` but also reports the source.
    public static func resolveDetailed(
        appID: String,
        catalog: AppCatalog?,
        compat: CompatDatabase?
    ) -> ResolvedCompatRating? {
        if let entry = bestCompatEntry(appID: appID, compat: compat) {
            return ResolvedCompatRating(entry: entry, source: .compatDB)
        }
        if let entry = recipeEntry(appID: appID, catalog: catalog) {
            return ResolvedCompatRating(entry: entry, source: .recipe)
        }
        return nil
    }

    /// Pick the most useful record from the compatibility database: prefer the
    /// `Mac` platform, then the highest rating, then the newest version. The
    /// first record wins on a full tie.
    public static func bestCompatEntry(appID: String, compat: CompatDatabase?) -> CompatEntry? {
        let entries = compat?.entries(appID: appID) ?? []
        return entries.reduce(into: CompatEntry?.none) { best, candidate in
            guard let current = best else {
                best = candidate
                return
            }
            if beats(candidate, current) { best = candidate }
        }
    }

    /// Build a rating record from a recipe catalog entry, deriving the numeric
    /// rating from the medal label when the catalog omitted it.
    public static func recipeEntry(appID: String, catalog: AppCatalog?) -> CompatEntry? {
        guard let app = catalog?.app(id: appID) else { return nil }
        let rating = app.rating ?? rating(forMedal: app.medal) ?? 0
        return CompatEntry(
            appID: app.id,
            name: app.name,
            platform: app.medalPlatform ?? "",
            version: app.version ?? "",
            medal: app.medal ?? "",
            rating: rating
        )
    }

    /// Map a CrossTie medal label to the canonical 1…5 rating.
    ///
    /// The mapping is taken from the shipped `crossover.tie`: `gold`/`ungold`
    /// carry rating 5, `silver`/`unsilver` rating 4 and `bronze`/`unbronze`
    /// rating 3 (`un…` labels mean *unverified at that level*, not lower — that
    /// is why the medals carry their own `rating` attribute). `knownnottowork`
    /// maps to 1. Unknown or absent labels return `nil`.
    public static func rating(forMedal medal: String?) -> Int? {
        guard let medal else { return nil }
        let label = medal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !label.isEmpty else { return nil }

        switch label {
        case "gold", "ungold":
            return 5
        case "silver", "unsilver":
            return 4
        case "bronze", "unbronze":
            return 3
        case "knownnottowork", "knownnottowork:", "nottowork", "won'twork", "doesn'twork":
            return 1
        case "untested", "unknown", "none":
            return nil
        default:
            // A generic "un<colour>" label rates like its base colour.
            if label.hasPrefix("un") {
                return rating(forMedal: String(label.dropFirst(2)))
            }
            return nil
        }
    }

    // MARK: - Ordering

    /// `candidate` is more useful than `current` (Mac preferred, then higher
    /// rating, then newer version). The first record wins on a full tie.
    private static func beats(_ candidate: CompatEntry, _ current: CompatEntry) -> Bool {
        let candidateMac = candidate.platform.caseInsensitiveCompare("Mac") == .orderedSame
        let currentMac = current.platform.caseInsensitiveCompare("Mac") == .orderedSame
        if candidateMac != currentMac { return candidateMac }
        if candidate.rating != current.rating { return candidate.rating > current.rating }
        switch current.version.compare(candidate.version, options: .numeric) {
        case .orderedAscending:
            return true
        default:
            return false
        }
    }
}
