import CorkKit
import Foundation

/// Tests for multi-Wine-version support. Owned by the runtime track.
private func wineComponentJSON(id: String, version: String, shaSeed: String = "a") -> String {
    """
    {"id":"\(id)","kind":"wine","name":"Wine \(version)","version":"\(version)","license":"LGPL-2.1-or-later","homepage":"https://example.com","sourceURL":"https://example.com","url":"https://example.com/\(id)-\(version).tar.xz","sha256":"\(String(repeating: shaSeed, count: 64))","size":1,"archiveFormat":"tar.xz","installRoot":""}
    """
}

private func graphicsComponentJSON(id: String, version: String) -> String {
    """
    {"id":"\(id)","kind":"graphics","name":"\(id)","version":"\(version)","license":"MIT","homepage":"https://example.com","sourceURL":"https://example.com","url":"https://example.com/\(id).tar.gz","sha256":"\(String(repeating: "c", count: 64))","size":1,"archiveFormat":"tar.gz","installRoot":""}
    """
}

/// Builds a two-Wine-entry manifest (11.18 default-first, 10.0 extra) plus one
/// graphics component, exercising the multi-version schema without any network.
private func multiWineManifestJSON(defaultWineVersion: String? = nil) -> Data {
    var fields: [String] = [
        "\"manifestVersion\":1",
        "\"updatedAt\":\"2026-10-16\"",
    ]
    if let defaultWineVersion {
        fields.append("\"defaultWineVersion\":\"\(defaultWineVersion)\"")
    }
    let components = [
        wineComponentJSON(id: "wine", version: "11.18", shaSeed: "a"),
        wineComponentJSON(id: "wine-10", version: "10.0", shaSeed: "b"),
        graphicsComponentJSON(id: "dxmt", version: "0.80"),
    ]
    fields.append("\"components\":[\(components.joined(separator: ","))]")
    return Data("{\(fields.joined(separator: ","))}".utf8)
}

private func makeWineTempHome() throws -> (paths: CorkPaths, root: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cork-wine-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return (CorkPaths(root: root), root)
}

func wineVersionsTests() -> [TestCase] {
    [
        TestCase(name: "multiWineManifestParses", body: {
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON()).validate()
            try expectEqual(manifest.wineComponents.count, 2, "two wine components")
            try expectEqual(manifest.wineVersions, ["11.18", "10.0"], "wine versions in order")
            try expectEqual(manifest.components.count, 3, "wine entries plus graphics")
            try expectEqual(manifest.component(id: "dxmt")?.kind, .graphics, "graphics still decoded")
        }),

        TestCase(name: "defaultWineIsFirstWithoutPinnedDefault", body: {
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON()).validate()
            try expectEqual(manifest.defaultWineComponent?.version, "11.18")
            try expectEqual(manifest.wineComponent?.version, "11.18", "wineComponent stays the default")
        }),

        TestCase(name: "pinnedDefaultWineVersionWins", body: {
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON(defaultWineVersion: "10.0")).validate()
            try expectEqual(manifest.defaultWineComponent?.version, "10.0")
            try expectEqual(manifest.wineComponent?.id, "wine-10")
        }),

        TestCase(name: "unknownPinnedDefaultFallsBackToFirst", body: {
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON(defaultWineVersion: "9.9")).validate()
            try expectEqual(manifest.defaultWineComponent?.version, "11.18", "unknown pin falls back to first wine")
        }),

        TestCase(name: "wineLookupByVersionAndID", body: {
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON()).validate()
            try expectEqual(manifest.wineComponent(forVersion: "10.0")?.id, "wine-10")
            try expectEqual(manifest.wineComponent(forVersion: "  11.18 ")?.id, "wine", "lookup trims whitespace")
            try expectEqual(manifest.wineComponent(forVersion: "wine-10")?.version, "10.0", "id fallback")
            try expect(manifest.wineComponent(forVersion: "9.9") == nil, "unknown version is nil")
            try expect(manifest.wineComponent(forVersion: "  ") == nil, "blank version is nil")
        }),

        TestCase(name: "unknownVersionErrors", body: {
            let home = try makeWineTempHome()
            defer { try? FileManager.default.removeItem(at: home.root) }
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON()).validate()
            let manager = try RuntimeManager(paths: home.paths, manifest: manifest)

            try expectThrows(CorkError.self, "requireWine with unknown version") {
                _ = try manager.requireWine(version: "9.9")
            }
            try expectThrows(CorkError.self, "select unknown version") {
                try manager.selectWineVersion("9.9")
            }
            try expectThrows(CorkError.self, "select known but uninstalled version") {
                try manager.selectWineVersion("11.18")
            }
        }),

        TestCase(name: "singleEntryManifestBackwardCompatible", body: {
            let manifest = try RuntimeManifest.loadBundled().validate()
            try expectEqual(manifest.wineComponents.count, 1, "bundled manifest has one wine entry")
            try expect(manifest.wineComponent != nil, "wineComponent is present")
            try expectEqual(manifest.defaultWineComponent?.version, manifest.wineComponent?.version)
            try expectEqual(manifest.wineVersions, [manifest.wineComponent!.version])

            let home = try makeWineTempHome()
            defer { try? FileManager.default.removeItem(at: home.root) }
            let manager = try RuntimeManager(paths: home.paths, manifest: manifest)
            try expect(manager.isWineReady == false, "empty home is not ready")
            try expect(manager.installedWineVersions().isEmpty, "nothing installed")
            try expect(manager.selectedWineVersion == nil, "nothing selected")
            try expectThrows(CorkError.self, "default requireWine still throws without an install") {
                _ = try manager.requireWine()
            }
        }),

        TestCase(name: "selectionResolvesInstalledWine", body: {
            let home = try makeWineTempHome()
            defer { try? FileManager.default.removeItem(at: home.root) }
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON()).validate()
            let manager = try RuntimeManager(paths: home.paths, manifest: manifest)

            guard let ten = manifest.wineComponent(forVersion: "10.0") else {
                throw TestFailure(description: "expected a 10.0 wine component")
            }
            try FileManager.default.createDirectory(
                at: manager.componentDirectory(ten),
                withIntermediateDirectories: true
            )
            try manager.store.writeMarker(for: ten, fileCount: 0)

            try expectEqual(manager.installedWineVersions(), ["10.0"], "only the marked version is installed")
            try expectEqual(manager.resolvedWineComponent()?.version, "11.18", "unselected falls back to default")
            try expect(manager.isWineReady == false, "default 11.18 is not installed")

            try manager.selectWineVersion("10.0")
            try expectEqual(manager.selectedWineVersion, "10.0")
            try expectEqual(manager.resolvedWineComponent()?.version, "10.0", "selection overrides default")
            try expect(manager.isWineReady, "selected installed wine makes the runtime ready")

            try manager.clearWineSelection()
            try expectEqual(manager.selectedWineVersion, nil as String?)
            try expectEqual(manager.resolvedWineComponent()?.version, "11.18", "cleared falls back to default")
        }),

        TestCase(name: "uninstallClearsStaleSelection", body: {
            let home = try makeWineTempHome()
            defer { try? FileManager.default.removeItem(at: home.root) }
            let manifest = try RuntimeManifest.load(from: multiWineManifestJSON()).validate()
            let manager = try RuntimeManager(paths: home.paths, manifest: manifest)

            guard let ten = manifest.wineComponent(forVersion: "10.0") else {
                throw TestFailure(description: "expected a 10.0 wine component")
            }
            try FileManager.default.createDirectory(
                at: manager.componentDirectory(ten),
                withIntermediateDirectories: true
            )
            try manager.store.writeMarker(for: ten, fileCount: 0)
            try manager.selectWineVersion("10.0")

            try manager.uninstall(componentIDs: [ten.id])
            try expectEqual(manager.selectedWineVersion, nil as String?, "stale selection is cleared")
            try expect(manager.installedWineVersions().isEmpty)
        }),
    ]
}
