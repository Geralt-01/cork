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

/// Parses `compatdb-*.dat`.
///
/// ## Format notes (best-effort, reverse-engineered 2026-02)
///
/// The container is *not* a known compression/archive format. Observations from
/// `compatdb-26.dat` (30,005 bytes):
///
/// - No magic for gzip (`1f 8b`), bzip2 (`BZh`), xz, zip (`PK`) or zlib
///   (no `78 9c`/`78 01`/`78 da` header). Raw-deflate at every offset also fails.
/// - Every byte is in the range `0x00…0x7f` (128 distinct values, zero bytes with
///   the high bit set), and the byte distribution is near-uniform
///   (≈6.55 bits/byte of entropy). That is consistent with an encrypted or
///   otherwise obfuscated 7-bit stream, not with plain text or a normal archive.
/// - The first bytes are `34 4c 48 0a` (`"4LH\n"`), i.e. an ASCII-looking header
///   rather than a `com.codeweavers`-style record list; a single-byte XOR does
///   not produce readable text and no repeating-key XOR key length stands out.
/// - A sibling `compatdb-26.dat.sha256` is a 256-byte blob (not a hex digest),
///   consistent with a signature/manifest over the encrypted payload.
///
/// Because CodeWeavers does not document the format, this parser is deliberately
/// conservative: it verifies the file is readable and then returns an empty map
/// so callers transparently fall back to recipe (`crossover.tie`) medals. It
/// never throws, even for malformed or unknown data.
public enum CompatDatabaseParser {
    /// The byte signature seen at the start of the shipped `compatdb-*.dat`
    /// files (`"4LH\n"`). Used only to recognise the encrypted container.
    static let encryptedHeader: [UInt8] = [0x34, 0x4c, 0x48, 0x0a]

    /// Parse a `compatdb-*.dat` file into `[appID: [CompatEntry]]`.
    ///
    /// Returns an empty map when the (undocumented, obfuscated) format cannot be
    /// decoded. Never throws for unrecognised data.
    public static func parse(fileURL: URL) throws -> [String: [CompatEntry]] {
        // Reading is the only guaranteed-safe operation; the payload itself is
        // an undocumented obfuscated binary (see the type documentation above).
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return [:]
        }
        _ = data
        return [:]
    }
}
