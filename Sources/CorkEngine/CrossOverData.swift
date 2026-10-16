import Foundation

/// Locates CrossOver data files that the *user* has on their machine.
///
/// Cork reads these only if present; it never bundles or redistributes them.
public enum CrossOverData {
    /// The CrossOver application-support directory, honouring `CORK_CROSSOVER_HOME`.
    public static func defaultDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["CORK_CROSSOVER_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("CrossOver", isDirectory: true)
    }

    /// Path to `tie/crossover.tie` if it exists.
    public static func defaultTieURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        firstExisting([
            defaultDirectory(environment: environment).appendingPathComponent("tie/crossover.tie"),
        ])
    }

    /// Path to the newest `compatdb-*.dat` if any exists.
    public static func defaultCompatDatabaseURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        let dir = defaultDirectory(environment: environment)
        let candidates = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("compatdb-") && $0.pathExtension == "dat" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        return firstExisting(candidates)
    }

    private static func firstExisting(_ urls: [URL]) -> URL? {
        urls.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
