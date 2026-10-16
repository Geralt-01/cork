import Foundation

public struct RuntimeManifest: Codable, Sendable {
    public let manifestVersion: Int
    public let updatedAt: String
    /// Optional version string marking which Wine component is the default.
    /// Absent (or pointing at an unknown version) falls back to the first
    /// `kind == .wine` component, preserving the single-entry behaviour.
    public let defaultWineVersion: String?
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

    /// Every Wine component in manifest order. May contain several entries so
    /// multiple Wine versions can coexist in the same Cork home.
    public var wineComponents: [Component] {
        components.filter { $0.kind == .wine }
    }

    /// The default Wine component. Kept as the primary entry point so existing
    /// callers keep working with a single-entry manifest.
    public var wineComponent: Component? {
        defaultWineComponent
    }

    /// Resolves the manifest's default Wine component: the entry named by
    /// `defaultWineVersion` when present and valid, otherwise the first Wine
    /// entry.
    public var defaultWineComponent: Component? {
        if let pinned = defaultWineVersion, !pinned.isEmpty,
           let match = wineComponent(forVersion: pinned) {
            return match
        }
        return wineComponents.first
    }

    /// Looks a Wine component up by its version string, falling back to a match
    /// on the component id. Matching is case-insensitive and whitespace
    /// tolerant.
    public func wineComponent(forVersion version: String) -> Component? {
        let needle = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return nil }
        return wineComponents.first { $0.version.lowercased() == needle }
            ?? wineComponents.first { $0.id.lowercased() == needle }
    }

    /// Version strings for every Wine component, in manifest order.
    public var wineVersions: [String] {
        wineComponents.map(\.version)
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
