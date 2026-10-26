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
        TestCase(name: "executablePathResolution", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-paths-\(UUID().uuidString)")
            let driveC = root.appendingPathComponent("drive_c", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(
                at: driveC.appendingPathComponent("Program Files/App", isDirectory: true),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: driveC.appendingPathComponent("users/tester", isDirectory: true),
                withIntermediateDirectories: true
            )
            let app = driveC.appendingPathComponent("Program Files/App/app.exe")
            let bare = driveC.appendingPathComponent("game.exe")
            try Data("bin".utf8).write(to: app)
            try Data("bin".utf8).write(to: bare)

            let bottle = Bottle(
                url: root,
                metadata: BottleMetadata(name: "Paths", wineVersion: "wine-11.18")
            )

            try expectEqual(
                bottle.resolveExecutablePath(#"C:\Program Files\App\app.exe"#).path,
                app.standardizedFileURL.path,
                "a Windows drive path resolves inside drive_c"
            )
            try expectEqual(
                bottle.resolveExecutablePath(#"%ProgramFiles%\App\app.exe"#).path,
                app.standardizedFileURL.path,
                "environment variables are expanded"
            )
            try expectEqual(
                bottle.resolveExecutablePath("C:/Program Files/App/app.exe").path,
                app.standardizedFileURL.path,
                "forward slashes are accepted"
            )
            try expectEqual(
                bottle.resolveExecutablePath("game.exe").path,
                bare.standardizedFileURL.path,
                "a bare name is looked up in drive_c"
            )
            try expectEqual(
                bottle.resolveExecutablePath("/tmp/outside.exe").path,
                "/tmp/outside.exe",
                "Unix absolute paths pass through"
            )
            try expect(
                bottle.windowsPathToUnix(#"\\server\share\app.exe"#) == nil,
                "UNC paths cannot be mapped into a prefix"
            )

            let dosdevices = root.appendingPathComponent("dosdevices", isDirectory: true)
            try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: dosdevices.appendingPathComponent("c:"),
                withDestinationURL: driveC
            )
            try FileManager.default.createSymbolicLink(
                at: dosdevices.appendingPathComponent("z:"),
                withDestinationURL: URL(fileURLWithPath: "/")
            )
            try expectEqual(
                bottle.windowsPath(forLocalPath: app.path),
                #"C:\Program Files\App\app.exe"#,
                "drive_c paths map to C:"
            )
            try expectEqual(
                bottle.windowsPath(forLocalPath: "/tmp/setup file.msi"),
                #"Z:\tmp\setup file.msi"#,
                "paths outside the prefix use Wine's Z: root drive"
            )
        }),
        TestCase(name: "bottleManagerRejectsTraversalNames", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-traversal-\(UUID().uuidString)")
            let paths = CorkPaths(root: root)
            defer { try? FileManager.default.removeItem(at: root) }
            try paths.createDirectories()

            let manager = try BottleManager(paths: paths)
            try expect(!manager.exists(named: "../escape"), "traversal name must not exist")
            try expectThrows(CorkError.self, "load traversal") {
                _ = try manager.load(named: "../escape")
            }
            try expectThrows(CorkError.self, "delete traversal") {
                try manager.delete(named: "../escape")
            }
        }),
        TestCase(name: "windowsVersionRegistryFields", body: {
            try expectEqual(WindowsVersion.win7.registryVersion, "6.1")
            try expectEqual(WindowsVersion.win7.registryMajor, 6)
            try expectEqual(WindowsVersion.win7.registryMinor, 1)
            try expectEqual(WindowsVersion.win10.registryVersion, "10.0")
            try expectEqual(WindowsVersion.win10.registryMajor, 10)
            try expectEqual(WindowsVersion.winxp.registryMajor, 5)
            try expectEqual(WindowsVersion.winxp.registryMinor, 1)
        }),
        TestCase(name: "newBottlesAreQuietByDefault", body: {
            try expectEqual(BottleSettings().debugChannels, "", "new bottles should not spam FIXME output")
            var settings = BottleSettings()
            try settings.apply(key: "debug", value: "off")
            try expectEqual(settings.debugChannels, "")
            try settings.apply(key: "debug", value: "+fixme,+loaddll")
            try expectEqual(settings.debugChannels, "+fixme,+loaddll")
        }),
    ]
}
