import Foundation

public struct RuntimeManifest: Codable, Sendable {
    public let manifestVersion: Int
    public let updatedAt: String
    public let components: [Component]

    public enum Kind: String, Codable, Sendable {
        case wine
        case graphics
    }

    public struct Component: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let kind: Kind
        public let name: String
        public let version: String
        public let license: String
        public let homepage: String
        public let sourceURL: String
        public let url: String
        public let sha256: String
        public let size: Int
        public let archiveFormat: String
        public let installRoot: String

        public var fileName: String { URL(string: url)?.lastPathComponent ?? id }
    }

    public func component(id: String) -> Component? {
        components.first { $0.id == id }
    }

    public var wineComponent: Component? {
        components.first { $0.kind == .wine }
    }
}

public extension RuntimeManifest {
    static func load(from data: Data) throws -> RuntimeManifest {
        do {
            return try JSONDecoder().decode(RuntimeManifest.self, from: data)
        } catch {
            throw CorkError.manifestInvalid(String(describing: error))
        }
    }

    static func loadBundled() throws -> RuntimeManifest {
        guard let url = Bundle.module.url(forResource: "RuntimeManifest", withExtension: "json") else {
            throw CorkError.manifestMissing
        }
        return try load(from: Data(contentsOf: url))
    }

    func validate() throws -> RuntimeManifest {
        guard manifestVersion == CorkVersion.manifestSchema else {
            throw CorkError.manifestInvalid("unexpected manifest version \(manifestVersion)")
        }
        for component in components {
            if component.id.isEmpty { throw CorkError.manifestInvalid("component with empty id") }
            if component.sha256.count != 64 { throw CorkError.manifestInvalid("\(component.id): sha256 must be 64 hex chars") }
        }
        return self
    }
}
