import Foundation
import CorkKit

func bottleTests() -> [TestCase] {
    [
        TestCase(name: "nameValidation", body: {
            try Bottle.validateName("My Game 1")
            try Bottle.validateName("game_1.0")
            try expectThrows(CorkError.self, "empty name") { try Bottle.validateName("") }
            try expectThrows(CorkError.self, "parent traversal") { try Bottle.validateName("../escape") }
            try expectThrows(CorkError.self, "slash") { try Bottle.validateName("bad/slash") }
            try expectThrows(CorkError.self, "hidden") { try Bottle.validateName(".hidden") }
        }),
        TestCase(name: "metadataRoundTrip", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-bottle-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            var bottle = Bottle(
                url: root,
                metadata: BottleMetadata(name: "Test", wineVersion: "wine-11.18")
            )
            try bottle.save()

            let loaded = try Bottle.load(at: root)
            try expectEqual(loaded.name, "Test")
            try expectEqual(loaded.metadata.wineVersion, "wine-11.18")
            try expect(loaded.settings.backend == .dxmt)
            try expect(FileManager.default.fileExists(atPath: loaded.metadataURL.path))
        }),
        TestCase(name: "loadMissingBottleThrows", body: {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cork-missing-\(UUID().uuidString)")
            try expectThrows(CorkError.self) { _ = try Bottle.load(at: url) }
        }),
        TestCase(name: "runtimeStoreMarkerRoundTrip", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-store-\(UUID().uuidString)")
            let paths = CorkPaths(root: root)
            try paths.createDirectories()
            defer { try? FileManager.default.removeItem(at: root) }

            let store = RuntimeStore(paths: paths)
            let manifest = try RuntimeManifest.loadBundled()
            guard let component = manifest.component(id: "dxmt") else {
                throw TestFailure(description: "dxmt missing from bundled manifest")
            }

            try expect(store.isInstalled(component) == false, "fresh store should be empty")
            try FileManager.default.createDirectory(
                at: paths.componentDirectory(id: component.id, version: component.version),
                withIntermediateDirectories: true
            )
            try store.writeMarker(for: component, fileCount: 3)
            try expect(store.isInstalled(component), "marker round trip")
            try expectEqual(store.record(for: component)?.fileCount, 3)
        }),
        TestCase(name: "graphicsInstallTracking", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-gfx-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

            var bottle = Bottle(
                url: root,
                metadata: BottleMetadata(name: "Gfx", wineVersion: "wine-11.18")
            )
            try bottle.save()

            try expect(bottle.metadata.graphicsFiles.isEmpty, "fresh bottle has no graphics files")
            try expect(bottle.graphicsDirectory.path.contains("cork"))
        }),
    ]
}
