import Foundation

/// Finds a *user-supplied* CrossOver `cxfixes.xml`.
///
/// Cork never bundles or redistributes CodeWeavers data; this only looks at
/// files already on the user's machine. The lookup honours the `CORK_CXFIXES`
/// environment override and otherwise looks in the CrossOver application
/// support directory (see ``CrossOverData``).
public enum CxFixesDiscovery {
    /// The user's `cxfixes.xml` if one exists, else `nil`.
    public static func candidateURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let fileManager = FileManager.default
        if let override = environment["CORK_CXFIXES"], !override.isEmpty {
            let url = URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        }
        let url = CrossOverData.defaultDirectory(environment: environment)
            .appendingPathComponent("cxfixes.xml")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Loads and parses the discovered file, returning `nil` when it is absent
    /// or cannot be understood. Never throws.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CxFixes? {
        guard let url = candidateURL(environment: environment) else { return nil }
        return try? CxFixes(fileURL: url)
    }
}
