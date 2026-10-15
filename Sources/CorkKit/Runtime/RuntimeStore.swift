import Foundation

public struct InstalledComponentRecord: Codable, Sendable {
    public let id: String
    public let version: String
    public let sha256: String
    public let installedAt: Date
    public let fileCount: Int
}

public struct RuntimeStore {
    public let paths: CorkPaths

    public init(paths: CorkPaths) {
        self.paths = paths
    }

    private static let markerName = ".cork-component.json"

    public func markerURL(for component: RuntimeManifest.Component) -> URL {
        paths.componentDirectory(id: component.id, version: component.version)
            .appendingPathComponent(Self.markerName)
    }

    public func record(for component: RuntimeManifest.Component) -> InstalledComponentRecord? {
        guard let data = try? Data(contentsOf: markerURL(for: component)) else { return nil }
        return try? JSONDecoder.cork.decode(InstalledComponentRecord.self, from: data)
    }

    public func isInstalled(_ component: RuntimeManifest.Component) -> Bool {
        guard let record = record(for: component) else { return false }
        return record.version == component.version && record.sha256.lowercased() == component.sha256.lowercased()
    }

    public func installedComponents(in manifest: RuntimeManifest) -> [RuntimeManifest.Component] {
        manifest.components.filter { isInstalled($0) }
    }

    public func writeMarker(
        for component: RuntimeManifest.Component,
        fileCount: Int
    ) throws {
        let record = InstalledComponentRecord(
            id: component.id,
            version: component.version,
            sha256: component.sha256,
            installedAt: Date(),
            fileCount: fileCount
        )
        let data = try JSONEncoder.cork.encode(record)
        try data.write(to: markerURL(for: component), options: .atomic)
    }

    public func remove(_ component: RuntimeManifest.Component) throws {
        let directory = paths.componentDirectory(id: component.id, version: component.version)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    public func removeAll() throws {
        for component in try RuntimeManifest.loadBundled().validate().components {
            try remove(component)
        }
    }

    public func fileCount(in directory: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return enumerator.allObjects.count
    }
}

extension JSONEncoder {
    public static var cork: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    public static var cork: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
