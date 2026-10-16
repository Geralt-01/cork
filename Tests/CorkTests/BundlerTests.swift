import CorkEngine
import CorkKit
import Foundation

/// Tests for macOS app bundling. Owned by the bundling track.
///
/// These never require a Wine runtime: `AppBundler.createBundle` only writes
/// files, and the generated launcher resolves Wine at launch time.
func bundlerTests() -> [TestCase] {
    /// A throwaway bottle that does not need Wine, backed by a temp directory.
    func makeBottle() throws -> (Bottle, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cork-bundle-bottle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bottle = Bottle(
            url: root,
            metadata: BottleMetadata(name: "TestBottle", wineVersion: "wine-11.18")
        )
        return (bottle, root)
    }

    func readPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            throw TestFailure(description: "Info.plist is not a dictionary")
        }
        return plist
    }

    return [
        TestCase(name: "createsAppStructure", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
            }

            let bundler = AppBundler()
            let appURL = try bundler.createBundle(
                name: "My Game",
                bottle: bottle,
                executable: "C:\\Program Files\\MyGame\\game.exe",
                arguments: ["--fullscreen"],
                outputDirectory: out
            )

            try expectEqual(appURL.lastPathComponent, "My Game.app")
            try expectEqual(appURL.deletingLastPathComponent().standardizedFileURL.path,
                            out.standardizedFileURL.path)

            let fm = FileManager.default
            let contents = appURL.appendingPathComponent("Contents")
            let info = contents.appendingPathComponent("Info.plist")
            let launcher = contents.appendingPathComponent("MacOS/My Game")
            let launchJSON = contents.appendingPathComponent("Resources/launch.json")

            try expect(fm.fileExists(atPath: contents.path), "Contents missing")
            try expect(fm.fileExists(atPath: info.path), "Info.plist missing")
            try expect(fm.fileExists(atPath: launcher.path), "launcher missing")
            try expect(fm.fileExists(atPath: launchJSON.path), "launch.json missing")
            try expect(fm.isExecutableFile(atPath: launcher.path), "launcher is not executable")
            try expect(fm.fileExists(atPath: contents.appendingPathComponent("PkgInfo").path),
                       "PkgInfo missing")

            let attributes = try fm.attributesOfItem(atPath: launcher.path)
            let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            try expect((permissions & 0o111) != 0, "launcher lacks execute bits")
        }),

        TestCase(name: "infoPlistHasExpectedKeys", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
            }

            let appURL = try AppBundler().createBundle(
                name: "My Game",
                bottle: bottle,
                executable: "/tmp/game.exe",
                outputDirectory: out
            )
            let plist = try readPlist(appURL.appendingPathComponent("Contents/Info.plist"))

            try expectEqual(plist["CFBundleName"] as? String, "My Game")
            try expectEqual(plist["CFBundleDisplayName"] as? String, "My Game")
            try expectEqual(plist["CFBundleIdentifier"] as? String, "tools.cork.app.my-game")
            try expectEqual(plist["CFBundleExecutable"] as? String, "My Game")
            try expectEqual(plist["CFBundlePackageType"] as? String, "APPL")
            try expectEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
            try expectEqual(plist["NSHighResolutionCapable"] as? Bool, true)
            try expect(plist["CFBundleIconFile"] == nil, "no icon expected without --icon")
        }),

        TestCase(name: "launchJSONRecordsResolvedProgram", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
            }

            let appURL = try AppBundler().createBundle(
                name: "Game",
                bottle: bottle,
                executable: "C:\\Games\\game.exe",
                arguments: ["-a", "-b"],
                outputDirectory: out
            )
            let data = try Data(contentsOf: appURL.appendingPathComponent("Contents/Resources/launch.json"))
            let config = try JSONDecoder.cork.decode(LaunchConfig.self, from: data)

            try expectEqual(config.bottle, "TestBottle")
            try expectEqual(config.arguments, ["-a", "-b"])
            try expectEqual(config.windowsExecutable, "C:\\Games\\game.exe")
            // C: is mapped into the bottle's drive_c.
            let expected = bottle.driveCDirectory.appendingPathComponent("Games/game.exe").path
            try expectEqual(config.executable, expected)

            // Default args are baked into the launcher (no JSON parsing at
            // runtime), and it delegates to `cork run`.
            let launcher = appURL.appendingPathComponent("Contents/MacOS/Game")
            let script = try String(contentsOf: launcher, encoding: .utf8)
            try expect(script.contains("'-a' '-b'"), "default args not baked into launcher")
            try expect(script.contains("exec \"${CORK}\" 'run' 'TestBottle'"),
                       "launcher does not delegate to 'cork run'")
        }),

        TestCase(name: "unixExecutablePassesThrough", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
            }

            let appURL = try AppBundler().createBundle(
                name: "Game",
                bottle: bottle,
                executable: "/Users/me/game.exe",
                outputDirectory: out
            )
            let data = try Data(contentsOf: appURL.appendingPathComponent("Contents/Resources/launch.json"))
            let config = try JSONDecoder.cork.decode(LaunchConfig.self, from: data)
            try expectEqual(config.executable, "/Users/me/game.exe")
        }),

        TestCase(name: "existingBundleIsReplacedSafely", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
            }

            let bundler = AppBundler()
            let first = try bundler.createBundle(
                name: "Game", bottle: bottle, executable: "/tmp/a.exe", outputDirectory: out
            )
            // A stray file from the "old" app must not survive the rebuild.
            let stray = first.appendingPathComponent("stray.txt")
            try Data("stale".utf8).write(to: stray)

            let second = try bundler.createBundle(
                name: "Game", bottle: bottle, executable: "/tmp/b.exe", outputDirectory: out
            )
            try expectEqual(first.path, second.path)
            try expect(!FileManager.default.fileExists(atPath: stray.path), "stale file survived")
            try expect(FileManager.default.fileExists(
                atPath: second.appendingPathComponent("Contents/Info.plist").path
            ), "rebuilt bundle is missing Info.plist")
        }),

        TestCase(name: "iconCopyIsReferenced", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            let icon = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-icon-\(UUID().uuidString).icns")
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
                try? FileManager.default.removeItem(at: icon)
            }
            // A pre-built .icns is copied verbatim, so no sips/iconutil needed.
            try Data("dummy-icns".utf8).write(to: icon)

            let appURL = try AppBundler().createBundle(
                name: "Game", bottle: bottle, executable: "/tmp/game.exe",
                iconPath: icon, outputDirectory: out
            )
            let resources = appURL.appendingPathComponent("Contents/Resources")
            try expect(FileManager.default.fileExists(atPath: resources.appendingPathComponent("AppIcon.icns").path),
                       "AppIcon.icns missing")
            let plist = try readPlist(appURL.appendingPathComponent("Contents/Info.plist"))
            try expectEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        }),

        TestCase(name: "badIconWarnsButSucceeds", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
            }
            let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).png")

            let appURL = try AppBundler().createBundle(
                name: "Game", bottle: bottle, executable: "/tmp/game.exe",
                iconPath: missing, outputDirectory: out
            )
            let plist = try readPlist(appURL.appendingPathComponent("Contents/Info.plist"))
            try expect(plist["CFBundleIconFile"] == nil, "no icon should be advertised")
            try expect(FileManager.default.fileExists(
                atPath: appURL.appendingPathComponent("Contents/MacOS/Game").path
            ), "bundle should still be created")
        }),

        TestCase(name: "rejectsUnsafeNames", body: {
            let (bottle, bottleRoot) = try makeBottle()
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-bundle-out-\(UUID().uuidString)", isDirectory: true)
            defer {
                try? FileManager.default.removeItem(at: out)
                try? FileManager.default.removeItem(at: bottleRoot)
            }
            let bundler = AppBundler()
            try expectThrows(CorkError.self, "path traversal") {
                _ = try bundler.createBundle(
                    name: "../escape", bottle: bottle, executable: "/tmp/a.exe", outputDirectory: out
                )
            }
            try expectThrows(CorkError.self, "empty name") {
                _ = try bundler.createBundle(
                    name: "  ", bottle: bottle, executable: "/tmp/a.exe", outputDirectory: out
                )
            }
            // Nothing escaped the output directory.
            try expect(!FileManager.default.fileExists(
                atPath: out.deletingLastPathComponent().appendingPathComponent("escape.app").path
            ), "bundle escaped the output directory")
        }),
    ]
}
