import Foundation

/// Streaming parser for the CrossTie (`c4p`) XML catalog.
///
/// This is a placeholder that compiles and returns an empty catalog. The engine
/// track replaces the body of ``parse(fileURL:)`` with a real streaming
/// (SAX) implementation. The signature must stay stable.
public enum CrossTieParser {
    /// Parse a CrossTie XML file into an in-memory ``CrossTieIndex``.
    ///
    /// TODO(engine): implement streaming parsing of `<app>` / `<appprofile>` /
    /// `<installprofile>` records. The file can be tens of MB, so do not build a
    /// full DOM.
    public static func parse(fileURL: URL) throws -> CrossTieIndex {
        _ = fileURL
        return CrossTieIndex(apps: [])
    }
}
