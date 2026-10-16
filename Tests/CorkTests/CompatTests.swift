import CorkEngine
import Foundation

/// A minimal in-memory ``AppCatalog`` for exercising ``CompatRating`` without
/// touching the 23 MB on-disk `crossover.tie`.
private struct StubCatalog: AppCatalog {
    let apps: [String: RecipeApp]
    let sourceDescription = "stub"

    init(_ apps: [RecipeApp]) {
        self.apps = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var appCount: Int { apps.count }
    func categories() -> [String] { [] }
    func search(_ query: CatalogQuery) -> [RecipeApp] { Array(apps.values) }
    func app(id: String) -> RecipeApp? { apps[id] }
}

/// Write inline bytes to a temporary file and remove it afterwards.
private func withTempFile(_ bytes: [UInt8], label: String, _ body: (URL) throws -> Void) throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cork-compat-\(label)-\(UUID().uuidString).dat")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(bytes).write(to: url)
    try body(url)
}

/// Tests for the compatibility database. Owned by the compat track.
func compatTests() -> [TestCase] {
    [
        TestCase(name: "compatDatabaseEmptyForOpaqueBinary", body: {
            // An inline stand-in for the shipped obfuscated `compatdb-*.dat`:
            // the `"4LH\n"` header plus a deterministic 7-bit pseudo-random
            // body. The parser must not throw and must yield no records so
            // callers fall back to recipe medals.
            var bytes: [UInt8] = [0x34, 0x4c, 0x48, 0x0a]
            bytes.reserveCapacity(1024)
            for i in 0..<1024 {
                bytes.append(UInt8((i &* 37 &+ 11) % 128))
            }

            try withTempFile(bytes, label: "opaque") { url in
                let database = try CompatDatabase(fileURL: url)
                try expectEqual(database.count, 0, "opaque binary must not fabricate records")
                try expectEqual(database.entries(appID: "com.codeweavers.c4.1"), [])
                try expectEqual(database.rating(appID: "com.codeweavers.c4.1", platform: "Mac"), nil)
            }
        }),

        TestCase(name: "compatDatabaseEmptyForMissingOrEmptyFile", body: {
            // Missing file: `init` throws, but `parse` returns an empty map so
            // the readable-file guard is the only failure mode.
            let missing = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-compat-missing-\(UUID().uuidString).dat")
            let fromMissing = try CompatDatabase(fileURL: missing)
            try expectEqual(fromMissing.count, 0)
            try expectEqual(CompatDatabaseParser.parse(fileURL: missing).isEmpty, true)

            // Empty file.
            try withTempFile([], label: "empty") { url in
                let empty = try CompatDatabase(fileURL: url)
                try expectEqual(empty.count, 0)
            }

            // A directory path is unreadable as data and must also be empty.
            let fromDirectory = try CompatDatabase(fileURL: FileManager.default.temporaryDirectory)
            try expectEqual(fromDirectory.count, 0)
        }),

        TestCase(name: "compatDatabaseEntryAndRatingLookups", body: {
            let entries = [
                CompatEntry(
                    appID: "com.example.word",
                    name: "Example Word",
                    platform: "Linux",
                    version: "9.0.0",
                    medal: "silver",
                    rating: 4
                ),
                CompatEntry(
                    appID: "com.example.word",
                    name: "Example Word",
                    platform: "Mac",
                    version: "12.0.0",
                    medal: "gold",
                    rating: 5
                ),
                CompatEntry(
                    appID: "com.example.metal",
                    name: "Metal Only",
                    platform: "Linux",
                    version: "10.0.0",
                    medal: "knownnottowork",
                    rating: 1
                ),
            ]
            let database = CompatDatabase(entries: entries)

            try expectEqual(database.count, 3)
            try expectEqual(database.entries(appID: "com.example.word").count, 2)
            try expectEqual(database.entries(appID: "com.example.word").first?.platform, "Linux" as String?,
                            "insertion order preserved")
            try expectEqual(database.entries(appID: "com.example.unknown"), [])

            // Platform matching is case-insensitive.
            try expectEqual(database.rating(appID: "com.example.word", platform: "Mac"), 5)
            try expectEqual(database.rating(appID: "com.example.word", platform: "mac"), 5)
            try expectEqual(database.rating(appID: "com.example.word", platform: "Linux"), 4)
            try expectEqual(database.rating(appID: "com.example.metal", platform: "Mac"), nil)
            try expectEqual(database.rating(appID: "com.example.unknown", platform: "Mac"), nil)
        }),

        TestCase(name: "compatRatingMapsMedalToRating", body: {
            try expectEqual(CompatRating.rating(forMedal: "gold"), 5)
            try expectEqual(CompatRating.rating(forMedal: "ungold"), 5)
            try expectEqual(CompatRating.rating(forMedal: "silver"), 4)
            try expectEqual(CompatRating.rating(forMedal: "unsilver"), 4)
            try expectEqual(CompatRating.rating(forMedal: "bronze"), 3)
            try expectEqual(CompatRating.rating(forMedal: "unbronze"), 3)
            try expectEqual(CompatRating.rating(forMedal: "knownnottowork"), 1)

            // Case/whitespace insensitive.
            try expectEqual(CompatRating.rating(forMedal: "  GOLD "), 5)

            // Unknown / absent labels are not rated.
            try expectEqual(CompatRating.rating(forMedal: nil), nil)
            try expectEqual(CompatRating.rating(forMedal: ""), nil)
            try expectEqual(CompatRating.rating(forMedal: "untested"), nil)
            try expectEqual(CompatRating.rating(forMedal: "made-up"), nil)
        }),

        TestCase(name: "compatRatingFallsBackToRecipeMedal", body: {
            // No compatibility database: the medal/rating comes from the recipe.
            let catalog = StubCatalog([
                RecipeApp(
                    id: "com.example.word",
                    name: "Example Word",
                    rating: nil,
                    medal: "silver",
                    medalPlatform: "Mac",
                    version: "12.0"
                ),
            ])

            let resolved = try requireRating(
                CompatRating.resolveDetailed(appID: "com.example.word", catalog: catalog, compat: nil)
            )
            try expectEqual(resolved.source, .recipe)
            try expectEqual(resolved.source.rawValue, "recipe")
            try expectEqual(resolved.entry.medal, "silver")
            try expectEqual(resolved.entry.rating, 4, "rating derived from the medal label")
            try expectEqual(resolved.entry.platform, "Mac")
            try expectEqual(resolved.entry.version, "12.0")

            // The plain `resolve` returns the same entry.
            try expectEqual(
                CompatRating.resolve(appID: "com.example.word", catalog: catalog, compat: nil)?.rating,
                4
            )
        }),

        TestCase(name: "compatRatingPrefersCompatDatabaseOverRecipe", body: {
            let catalog = StubCatalog([
                RecipeApp(
                    id: "com.example.word",
                    name: "Example Word",
                    rating: 5,
                    medal: "gold",
                    medalPlatform: "Mac"
                ),
            ])
            let compat = CompatDatabase(entries: [
                CompatEntry(
                    appID: "com.example.word",
                    name: "Example Word",
                    platform: "Linux",
                    version: "9.0.0",
                    medal: "bronze",
                    rating: 3
                ),
            ])

            let resolved = try requireRating(
                CompatRating.resolveDetailed(appID: "com.example.word", catalog: catalog, compat: compat)
            )
            try expectEqual(resolved.source, .compatDB)
            try expectEqual(resolved.source.rawValue, "compatdb")
            try expectEqual(resolved.entry.rating, 3, "compat DB wins over the recipe medal")
            try expectEqual(resolved.entry.platform, "Linux")
        }),

        TestCase(name: "compatRatingPrefersMacThenHighest", body: {
            let compat = CompatDatabase(entries: [
                CompatEntry(appID: "a", name: "A", platform: "Linux", version: "12.0", medal: "gold", rating: 5),
                CompatEntry(appID: "a", name: "A", platform: "Mac", version: "9.0", medal: "silver", rating: 4),
            ])
            let best = try requireRating(CompatRating.bestCompatEntry(appID: "a", compat: compat))
            try expectEqual(best.platform, "Mac", "Mac preferred over a higher Linux rating")
            try expectEqual(best.rating, 4)

            let highest = CompatDatabase(entries: [
                CompatEntry(appID: "b", name: "B", platform: "Linux", version: "10.0", medal: "bronze", rating: 3),
                CompatEntry(appID: "b", name: "B", platform: "Linux", version: "9.0", medal: "gold", rating: 5),
            ])
            try expectEqual(CompatRating.bestCompatEntry(appID: "b", compat: highest)?.rating, 5)
        }),

        TestCase(name: "compatRatingReturnsNilWhenUnknown", body: {
            try expectEqual(CompatRating.resolve(appID: "nope", catalog: nil, compat: nil), nil)
            try expectEqual(
                CompatRating.resolveDetailed(appID: "nope", catalog: StubCatalog([]), compat: CompatDatabase(entries: [])),
                nil
            )
            // A recipe without any medal or rating is still returned, with 0.
            let catalog = StubCatalog([RecipeApp(id: "bare", name: "Bare")])
            let entry = try requireRating(CompatRating.resolve(appID: "bare", catalog: catalog, compat: nil))
            try expectEqual(entry.rating, 0)
            try expectEqual(entry.medal, "")
        }),
    ]
}

private func requireRating(_ entry: CompatEntry?) throws -> CompatEntry {
    guard let entry else {
        throw TestFailure(description: "expected a rating, got nil")
    }
    return entry
}

private func requireRating(_ resolved: ResolvedCompatRating?) throws -> ResolvedCompatRating {
    guard let resolved else {
        throw TestFailure(description: "expected a resolved rating, got nil")
    }
    return resolved
}
