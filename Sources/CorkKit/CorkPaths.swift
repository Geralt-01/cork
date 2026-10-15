import Foundation

public struct CorkPaths: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CorkPaths {
        if let override = environment["CORK_HOME"], !override.isEmpty {
            return CorkPaths(root: URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return CorkPaths(root: base.appendingPathComponent("Cork", isDirectory: true))
    }

    public var runtimesDirectory: URL {
        root.appendingPathComponent("Runtimes", isDirectory: true)
    }

    public var bottlesDirectory: URL {
        root.appendingPathComponent("Bottles", isDirectory: true)
    }

    public var cacheDirectory: URL {
        root.appendingPathComponent("Cache", isDirectory: true)
    }

    public func componentDirectory(id: String, version: String) -> URL {
        runtimesDirectory
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
    }

    public func bottleDirectory(named name: String) -> URL {
        bottlesDirectory.appendingPathComponent(name, isDirectory: true)
    }

    public func createDirectories() throws {
        let fm = FileManager.default
        for directory in [root, runtimesDirectory, bottlesDirectory, cacheDirectory] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
