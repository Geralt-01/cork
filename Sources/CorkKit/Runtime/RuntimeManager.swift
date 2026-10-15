import Foundation

public enum RuntimeInstallEvent: Sendable {
    case alreadyInstalled(id: String)
    case downloading(id: String, bytes: Int)
    case verifying(id: String)
    case extracting(id: String)
    case installed(id: String, location: String)
}

public struct RuntimeManager {
    public let paths: CorkPaths
    public let manifest: RuntimeManifest
    public let store: RuntimeStore

    public init(paths: CorkPaths, manifest: RuntimeManifest) throws {
        self.paths = paths
        self.manifest = try manifest.validate()
        self.store = RuntimeStore(paths: paths)
    }

    public init(paths: CorkPaths = .resolve()) throws {
        try self.init(paths: paths, manifest: RuntimeManifest.loadBundled())
    }

    public func installedComponents() -> [RuntimeManifest.Component] {
        store.installedComponents(in: manifest)
    }

    public func isInstalled(id: String) throws -> Bool {
        guard let component = manifest.component(id: id) else {
            throw CorkError.componentUnknown(id: id)
        }
        return store.isInstalled(component)
    }

    public var isWineReady: Bool {
        guard let wine = manifest.wineComponent else { return false }
        return store.isInstalled(wine)
    }

    public func requireWine() throws -> WineInstallation {
        guard let wine = manifest.wineComponent else {
            throw CorkError.manifestInvalid("manifest has no wine component")
        }
        guard store.isInstalled(wine) else {
            throw CorkError.runtimeNotInstalled
        }
        let directory = paths.componentDirectory(id: wine.id, version: wine.version)
        return try WineInstallation.detect(in: directory)
    }

    public func componentDirectory(_ component: RuntimeManifest.Component) -> URL {
        paths.componentDirectory(id: component.id, version: component.version)
    }

    public func install(
        componentIDs: [String]? = nil,
        force: Bool = false,
        onEvent: @escaping @Sendable (RuntimeInstallEvent) -> Void = { _ in },
        onDownloadProgress: @escaping @Sendable (String, DownloadProgress) -> Void = { _, _ in }
    ) async throws {
        try paths.createDirectories()
        let targets = try resolveTargets(componentIDs)
        for component in targets {
            if !force, store.isInstalled(component) {
                onEvent(.alreadyInstalled(id: component.id))
                continue
            }
            try await installComponent(
                component,
                onEvent: onEvent,
                onDownloadProgress: onDownloadProgress
            )
        }
    }

    private func resolveTargets(_ ids: [String]?) throws -> [RuntimeManifest.Component] {
        guard let ids else { return manifest.components }
        return try ids.map { id in
            guard let component = manifest.component(id: id) else {
                throw CorkError.componentUnknown(id: id)
            }
            return component
        }
    }

    private func installComponent(
        _ component: RuntimeManifest.Component,
        onEvent: @escaping @Sendable (RuntimeInstallEvent) -> Void,
        onDownloadProgress: @escaping @Sendable (String, DownloadProgress) -> Void
    ) async throws {
        guard let sourceURL = URL(string: component.url) else {
            throw CorkError.manifestInvalid("\(component.id): invalid url")
        }
        let archive = paths.cacheDirectory.appendingPathComponent(component.fileName)

        var archiveIsValid = false
        if FileManager.default.fileExists(atPath: archive.path) {
            archiveIsValid = (try? Integrity.sha256(ofFileAt: archive)) == component.sha256.lowercased()
            if !archiveIsValid {
                try? FileManager.default.removeItem(at: archive)
            }
        }

        if !archiveIsValid {
            onEvent(.downloading(id: component.id, bytes: component.size))
            try await Downloader.download(from: sourceURL, to: archive) { progress in
                onDownloadProgress(component.id, progress)
            }
        }

        onEvent(.verifying(id: component.id))
        try Integrity.verify(file: archive, expected: component.sha256)

        onEvent(.extracting(id: component.id))
        let destination = componentDirectory(component)
        guard let format = Archive.Format(rawValue: component.archiveFormat) else {
            throw CorkError.manifestInvalid("\(component.id): unsupported archive format \(component.archiveFormat)")
        }
        try Archive.extract(
            archive: archive,
            to: destination,
            installRoot: component.installRoot,
            format: format
        )

        try store.writeMarker(for: component, fileCount: store.fileCount(in: destination))
        try? FileManager.default.removeItem(at: archive)
        onEvent(.installed(id: component.id, location: destination.path))
    }

    public struct VerificationResult: Sendable {
        public let id: String
        public let name: String
        public let version: String
        public let installed: Bool
        public let detail: String
    }

    public func verify() -> [VerificationResult] {
        manifest.components.map { component in
            guard let record = store.record(for: component) else {
                return VerificationResult(
                    id: component.id,
                    name: component.name,
                    version: component.version,
                    installed: false,
                    detail: "not installed"
                )
            }
            let matches = record.version == component.version
                && record.sha256.lowercased() == component.sha256.lowercased()
            let directory = componentDirectory(component)
            let exists = FileManager.default.fileExists(atPath: directory.path)
            return VerificationResult(
                id: component.id,
                name: component.name,
                version: component.version,
                installed: matches && exists,
                detail: matches ? (exists ? "ok (\(record.fileCount) files)" : "marked installed but missing") : "version mismatch"
            )
        }
    }

    public func uninstall(componentIDs: [String]) throws {
        for component in try resolveTargets(componentIDs) {
            try store.remove(component)
        }
    }
}
