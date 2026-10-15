import Foundation
import CorkKit

func manifestTests() -> [TestCase] {
    [
        TestCase(name: "bundledManifestDecodesAndValidates", body: {
            let manifest = try RuntimeManifest.loadBundled().validate()
            try expectEqual(manifest.manifestVersion, CorkVersion.manifestSchema)
            try expect(manifest.wineComponent != nil, "wine component")
            try expect(manifest.component(id: "dxmt") != nil, "dxmt component")
            try expect(manifest.component(id: "dxvk") != nil, "dxvk component")
        }),
        TestCase(name: "everyComponentHasSha256AndURL", body: {
            let manifest = try RuntimeManifest.loadBundled()
            for component in manifest.components {
                try expectEqual(component.sha256.count, 64, "\(component.id) sha256 length")
                try expect(URL(string: component.url) != nil, "\(component.id) url")
                try expectEqual(component.fileName, URL(string: component.url)!.lastPathComponent, "\(component.id) fileName")
            }
        }),
        TestCase(name: "invalidManifestIsRejected", body: {
            let json = #"{"manifestVersion":1,"updatedAt":"x","components":[{"id":"wine","kind":"wine","name":"W","version":"1","license":"x","homepage":"x","sourceURL":"x","url":"https://example.com/a.tar.xz","sha256":"short","size":1,"archiveFormat":"tar.xz","installRoot":""}]}"#
            let manifest = try RuntimeManifest.load(from: Data(json.utf8))
            try expectThrows(CorkError.self, "invalid manifest must be rejected") {
                _ = try manifest.validate()
            }
        }),
        TestCase(name: "unknownComponentIsNil", body: {
            let manifest = try RuntimeManifest.loadBundled()
            try expect(manifest.component(id: "does-not-exist") == nil)
        }),
        TestCase(name: "readyManagedRuntimeConstructs", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-test-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let manager = try RuntimeManager(paths: CorkPaths(root: root), manifest: RuntimeManifest.loadBundled())
            try expect(manager.isWineReady == false, "empty home should not be ready")
            try expectThrows(CorkError.self) {
                _ = try manager.requireWine()
            }
        }),
        TestCase(name: "manifestHasNoPlaceholderDigests", body: {
            let manifest = try RuntimeManifest.loadBundled()
            for component in manifest.components {
                try expect(component.sha256.lowercased().contains("pending") == false, "\(component.id) still pending")
                try expect(component.sha256.rangeOfCharacter(from: .decimalDigits.union(.letters)) != nil)
            }
        }),
    ]
}
