import Foundation

/// Reads a CrossTie-format recipe catalog — the `crossover.tie` XML shipped by
/// CrossOver.
///
/// Cork never bundles or redistributes CodeWeavers' data. This type only parses
/// a file that the *user* supplies (for example their own CrossOver
/// installation, or a catalog they have a license to use).
///
/// The file is large (tens of megabytes, thousands of `<app>` records), so the
/// implementation must stream rather than load the whole DOM.
///
/// NOTE: frozen CorkEngine API surface. `CrossTieParser` in this module owns the
/// implementation; this struct should keep this initializer and `AppCatalog`
/// conformance stable.
public struct CrossTieCatalog: AppCatalog {
    public let fileURL: URL
    private let index: CrossTieIndex

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.index = try CrossTieParser.parse(fileURL: fileURL)
    }

    public var sourceDescription: String { fileURL.lastPathComponent }
    public var appCount: Int { index.apps.count }
    public func categories() -> [String] { index.categories }

    public func search(_ query: CatalogQuery) -> [RecipeApp] {
        index.search(query)
    }

    public func app(id: String) -> RecipeApp? { index.app(id: id) }

    /// Cheap sniff test used to avoid trying to parse unrelated XML files.
    public static func looksLikeCrossTie(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 256)) ?? Data()
        let text = String(decoding: head, as: UTF8.self)
        return text.contains("<c4p") || text.contains("highlightedapps")
    }
}

/// In-memory index of a parsed CrossTie catalog. Built by ``CrossTieParser``.
///
/// NOTE: frozen CorkEngine API surface (used by `CrossTieCatalog`).
public struct CrossTieIndex: Sendable {
    public let apps: [RecipeApp]
    public let categories: [String]
    private let byID: [String: RecipeApp]
    private let normalized: [(app: RecipeApp, haystack: String)]

    public init(apps: [RecipeApp]) {
        self.apps = apps
        self.categories = Array(Set(apps.compactMap(\.category))).sorted()
        self.byID = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.normalized = apps.map { app in
            let haystack = [
                app.name,
                app.summary ?? "",
                app.category ?? "",
                app.dependencies.joined(separator: " "),
            ]
            .joined(separator: " ")
            .lowercased()
            return (app, haystack)
        }
    }

    public func app(id: String) -> RecipeApp? { byID[id] }

    public func search(_ query: CatalogQuery) -> [RecipeApp] {
        let needle = query.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let categorySet = Set(query.categories)
        var results: [RecipeApp] = []
        for entry in normalized {
            let app = entry.app
            if !needle.isEmpty, !entry.haystack.contains(needle) { continue }
            if !categorySet.isEmpty, !(app.category.map(categorySet.contains) ?? false) { continue }
            if let minRating = query.minRating, (app.rating ?? 0) < minRating { continue }
            if let platform = query.platform, !app.platforms.isEmpty, !app.platforms.contains(platform) { continue }
            results.append(app)
        }
        // Apps with a real installer first, then by name.
        results.sort { lhs, rhs in
            if lhs.hasInstaller != rhs.hasInstaller { return lhs.hasInstaller }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        if query.offset > 0 {
            results = Array(results.dropFirst(query.offset))
        }
        if query.limit >= 0 {
            results = Array(results.prefix(query.limit))
        }
        return results
    }
}
