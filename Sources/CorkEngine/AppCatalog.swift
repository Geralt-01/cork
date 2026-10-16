import Foundation

/// A provider-neutral search request against an ``AppCatalog``.
public struct CatalogQuery: Sendable, Equatable {
    /// Free-text match against app names / descriptions. Empty matches everything.
    public var text: String
    /// Restrict to these categories (empty means any).
    public var categories: [String]
    /// Minimum medal rating (1…5). `nil` means any.
    public var minRating: Int?
    /// Restrict to a platform (`Mac`, `Linux`, …). `nil` means any.
    public var platform: String?
    /// Maximum number of results to return.
    public var limit: Int
    /// Number of results to skip (paging).
    public var offset: Int

    public init(
        text: String = "",
        categories: [String] = [],
        minRating: Int? = nil,
        platform: String? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.text = text
        self.categories = categories
        self.minRating = minRating
        self.platform = platform
        self.limit = limit
        self.offset = offset
    }
}

/// A read-only, searchable catalog of installable applications.
///
/// NOTE: frozen CorkEngine API surface. Implementations live in this module.
public protocol AppCatalog: Sendable {
    /// Human-readable description of where this catalog came from.
    var sourceDescription: String { get }
    /// Total number of applications in the catalog.
    var appCount: Int { get }
    /// All distinct categories, sorted.
    func categories() -> [String]
    /// Search the catalog.
    func search(_ query: CatalogQuery) -> [RecipeApp]
    /// Look up a single app by id.
    func app(id: String) -> RecipeApp?
}

public extension AppCatalog {
    /// Convenience: a simple text search with default limits.
    func search(_ text: String, limit: Int = 100) -> [RecipeApp] {
        search(CatalogQuery(text: text, limit: limit))
    }
}
