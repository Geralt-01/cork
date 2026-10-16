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
/// database is simply empty and callers fall back to recipe medals
/// (see ``CompatRating``).
///
/// NOTE: frozen CorkEngine API surface. New members may be added (additive),
/// but existing members keep their signatures.
public struct CompatDatabase: Sendable {
    /// The file the database was loaded from. For in-memory databases built via
    /// ``init(entries:fileURL:)`` this is metadata only and may be a placeholder.
    public let fileURL: URL
    private let entriesByApp: [String: [CompatEntry]]

    /// Load and parse a `compatdb-*.dat` file.
    ///
    /// ``CompatDatabaseParser/parse(fileURL:)`` never throws for unrecognised
    /// data; it returns an empty map. An unreadable or missing file therefore
    /// yields an empty database rather than an error.
    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.entriesByApp = try CompatDatabaseParser.parse(fileURL: fileURL)
    }

    /// Build an in-memory database from already-known entries.
    ///
    /// This is additive to the frozen surface: it lets callers that obtain
    /// ratings from a non-CrossOver source (or tests) exercise the lookup API
    /// without going through the undocumented binary container. Lookup order is
    /// preserved per app id.
    public init(entries: [CompatEntry], fileURL: URL = CompatDatabase.inMemoryURL) {
        self.fileURL = fileURL
        var map: [String: [CompatEntry]] = [:]
        for entry in entries {
            map[entry.appID, default: []].append(entry)
        }
        self.entriesByApp = map
    }

    /// Placeholder `fileURL` for ``init(entries:fileURL:)`` when no file exists.
    public static let inMemoryURL = URL(fileURLWithPath: "/dev/null")

    /// Total number of rating records parsed.
    public var count: Int { entriesByApp.values.reduce(0) { $0 + $1.count } }

    /// All rating records for an application id, in insertion order.
    public func entries(appID: String) -> [CompatEntry] { entriesByApp[appID] ?? [] }

    /// The numeric rating for an app on a given platform, if known.
    ///
    /// Platform matching is case-insensitive; the first matching record wins.
    public func rating(appID: String, platform: String) -> Int? {
        entriesByApp[appID]?
            .first { $0.platform.caseInsensitiveCompare(platform) == .orderedSame }?
            .rating
    }
}

/// Parses `compatdb-*.dat`.
///
/// ## Format notes (best-effort, reverse-engineered 2026-02 / 2026-10)
///
/// The container is *not* a known compression/archive format, and Cork does
/// **not** attempt to decode it. `parse` therefore returns an **empty map** for
/// the shipped CodeWeavers file; callers fall back to recipe
/// (`crossover.tie`) medals via ``CompatRating``. It never throws.
///
/// Observations from the shipped `compatdb-26.dat` (30,005 bytes):
///
/// - First bytes are `34 4c 48 0a` (`"4LH\n"`), an ASCII-looking header rather
///   than a `com.codeweavers`-style record list.
/// - Every byte is in the range `0x00…0x7f` (no byte has the high bit set); the
///   distribution is near-uniform (128 distinct values, ≈6.55 bits/byte of
///   entropy, ≈56% printable). That is consistent with an encrypted/obfuscated
///   7-bit stream, not with plain text or a normal archive.
/// - No magic for gzip (`1f 8b`), bzip2 (`BZh`), xz (`fd 37 7a 58 5a`), zip
///   (`PK`), SQLite (`SQLite format 3`) or zlib (`78 9c`/`78 01`/`78 da`).
///   Raw-deflate decompression at every offset fails (the one apparent hit is
///   repetitive decoder noise).
/// - Single-byte XOR over all 128 keys never exceeds ≈0.94 printable and never
///   yields readable text; delta schemes (`c[i]^c[i-1]`, `c[i]-c[i-1] mod 128`)
///   *increase* the entropy, and 7-bit→8-bit unpacking yields 39% printable
///   noise. A `compatdb-*.dat.sha256` sibling is a 256-byte high-entropy blob
///   (RSA-2048-sized), i.e. a signature, not a hex digest — the payload is
///   signed and obfuscated.
/// - The payload is not random, though: exact 84-byte blocks recur, and the GCD
///   of the distances between every repeated 24-byte block is `78`
///   (`78 = 2 · 3 · 13`), i.e. there is structure at a 78-byte stride — likely
///   fixed-size encrypted records. No periodic XOR/ADD/SUB keystream with a
///   period dividing 78 produces readable plaintext (per-column frequency
///   analysis just centres the bytes in printable ASCII), so the record bodies
///   are encrypted or otherwise keyed and cannot be recovered without the
///   CodeWeavers key/scheme.
///
/// Because CodeWeavers does not document the format, this parser is deliberately
/// conservative: it verifies the file is readable and then returns an empty map.
public enum CompatDatabaseParser {
    /// The byte signature seen at the start of the shipped `compatdb-*.dat`
    /// files (`"4LH\n"`). Used only to recognise the encrypted container.
    static let encryptedHeader: [UInt8] = [0x34, 0x4c, 0x48, 0x0a]

    /// Parse a `compatdb-*.dat` file into `[appID: [CompatEntry]]`.
    ///
    /// Returns an empty map when the (undocumented, obfuscated) format cannot be
    /// decoded. Never throws for unrecognised, malformed, missing or unreadable
    /// data.
    public static func parse(fileURL: URL) throws -> [String: [CompatEntry]] {
        // Reading is the only guaranteed-safe operation; the payload itself is
        // an undocumented obfuscated binary (see the type documentation above).
        // We deliberately do not fabricate records from it.
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else {
            return [:]
        }
        _ = data
        return [:]
    }
}
