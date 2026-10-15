import Foundation

public struct PinnedProgram: Codable, Sendable, Hashable {
    public var name: String
    public var path: String
    public var arguments: [String]

    public init(name: String, path: String, arguments: [String] = []) {
        self.name = name
        self.path = path
        self.arguments = arguments
    }
}

public struct BottleMetadata: Codable, Sendable {
    public var schemaVersion: Int
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var wineVersion: String
    public var corkVersion: String
    public var settings: BottleSettings
    public var graphicsFiles: [String]
    public var pins: [PinnedProgram]

    public init(
        name: String,
        wineVersion: String,
        settings: BottleSettings = BottleSettings()
    ) {
        self.schemaVersion = CorkVersion.bottleSettingsSchema
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.wineVersion = wineVersion
        self.corkVersion = CorkVersion.current
        self.settings = settings
        self.graphicsFiles = []
        self.pins = []
    }
}

public struct Bottle: Sendable, Identifiable {
    public let url: URL
    public var metadata: BottleMetadata

    public init(url: URL, metadata: BottleMetadata) {
        self.url = url
        self.metadata = metadata
    }

    public var id: String { metadata.name }
    public var name: String { metadata.name }
    public var settings: BottleSettings { metadata.settings }

    public var corkDirectory: URL {
        url.appendingPathComponent("cork", isDirectory: true)
    }

    public var metadataURL: URL {
        corkDirectory.appendingPathComponent("metadata.json")
    }

    public var graphicsDirectory: URL {
        corkDirectory.appendingPathComponent("graphics", isDirectory: true)
    }

    public var logsDirectory: URL {
        corkDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public var driveCDirectory: URL {
        url.appendingPathComponent("drive_c", isDirectory: true)
    }

    public var system32Directory: URL {
        driveCDirectory.appendingPathComponent("windows/system32", isDirectory: true)
    }

    public var syswow64Directory: URL {
        driveCDirectory.appendingPathComponent("windows/syswow64", isDirectory: true)
    }

    public var exists: Bool {
        FileManager.default.fileExists(atPath: metadataURL.path)
    }

    public static func load(at url: URL) throws -> Bottle {
        let metadataURL = url.appendingPathComponent("cork/metadata.json")
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw CorkError.bottleNotFound(name: url.lastPathComponent)
        }
        let metadata = try JSONDecoder.cork.decode(BottleMetadata.self, from: Data(contentsOf: metadataURL))
        return Bottle(url: url, metadata: metadata)
    }

    public mutating func save() throws {
        metadata.updatedAt = Date()
        try FileManager.default.createDirectory(at: corkDirectory, withIntermediateDirectories: true)
        try JSONEncoder.cork.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    public func latestLogFile() -> URL? {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        return entries
            .filter { $0.pathExtension == "log" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            .first
    }

    public static func validateName(_ name: String) throws {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 _.-")
        guard !name.isEmpty, name.count <= 64,
              name.rangeOfCharacter(from: allowed.inverted) == nil,
              !name.hasPrefix(".") else {
            throw CorkError.invalidBottleName(name: name)
        }
    }
}
