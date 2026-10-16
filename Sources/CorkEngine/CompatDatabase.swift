import Foundation

/// One application rating from the CrossOver compatibility database.
public struct CompatEntry: Sendable, Hashable {
    public var appID: String
    public var name: String
    public var platform: String
    public var version: String
    public var medal: String
    public var rating: Int

    public init(
        appID: String,
        name: String,
        platform: String,
        version: String,
        medal: String,
        rating: Int
    ) {
        self.appID = appID
        self.name = name
        self.platform = platform
        self.version = version
        self.medal = medal
        self.rating = rating
    }
}

/// Reads the CrossOver compatibility database (`compatdb-*.dat`).
///
/// As with ``CrossTieCatalog``, Cork only reads a *user supplied* file; it never
/// ships CodeWeavers data. The on-disk format is a proprietary/obfuscated
/// binary, so this is best-effort: if the file cannot be understood, the
/// database is simply empty and callers fall back to recipe medals.
///
/// NOTE: frozen CorkEngine API surface.
public struct CompatDatabase: Sendable {
    public let fileURL: URL
    private let entriesByApp: [String: [CompatEntry]]

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.entriesByApp = try CompatDatabaseParser.parse(fileURL: fileURL)
    }

    /// Total number of rating records parsed.
    public var count: Int { entriesByApp.values.reduce(0) { $0 + $1.count } }

    /// All rating records for an application id.
    public func entries(appID: String) -> [CompatEntry] { entriesByApp[appID] ?? [] }

    /// The numeric rating for an app on a given platform, if known.
    public func rating(appID: String, platform: String) -> Int? {
        entriesByApp[appID]?
            .first { $0.platform.caseInsensitiveCompare(platform) == .orderedSame }?
            .rating
    }
}

/// Parses `compatdb-*.dat`. Placeholder pending the engine track.
///
/// TODO(engine): reverse the container format (it is not plain text) and return
/// `[appID: [CompatEntry]]`. Return an empty map (do not throw) if the format is
/// unknown, so the rest of Cork keeps working.
public enum CompatDatabaseParser {
    public static func parse(fileURL: URL) throws -> [String: [CompatEntry]] {
        _ = fileURL
        return [:]
    }
}
