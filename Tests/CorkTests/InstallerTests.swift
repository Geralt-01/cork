import CorkEngine
import CorkKit
import Foundation

/// Tests for the installer executor. Owned by the install-b track.
func installerTests() -> [TestCase] {
    [
        TestCase(name: "downloadFileNameDerivation", body: {
            try expectEqual(
                InstallPlanner.fileName(forURL: "https://example.com/foo/Setup.exe", explicit: nil),
                "Setup.exe"
            )
            try expectEqual(
                InstallPlanner.fileName(forURL: "https://example.com/app%20Setup.zip?token=1#frag", explicit: nil),
                "app Setup.zip"
            )
            try expectEqual(
                InstallPlanner.fileName(forURL: "https://example.com/foo/Setup.exe", explicit: "custom.dmg"),
                "custom.dmg"
            )
            try expectEqual(
                InstallPlanner.fileName(forURL: "https://example.com/x", explicit: "../../etc/passwd"),
                "passwd"
            )
            try expectEqual(
                InstallPlanner.fileName(forURL: "https://example.com/x", explicit: "a/b/c.zip"),
                "c.zip"
            )
            try expect(InstallPlanner.fileName(forURL: "", explicit: nil) == nil, "empty url derives nothing")
            try expectEqual(
                InstallPlanner.fileName(
                    forURL: "https://sourceforge.net/projects/sevenzip/files/7-Zip/9.20/7z920.exe/download",
                    explicit: nil
                ),
                "7z920.exe",
                "a trailing generic '/download' segment is skipped"
            )
            try expect(InstallPlanner.isZip("Setup.ZIP"), "case-insensitive zip detection")
            try expect(!InstallPlanner.isZip("Setup.exe"), "exe is not a zip")
        }),

        TestCase(name: "installerGlobResolution", body: {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-glob-\(UUID().uuidString)")
            let driveC = root.appendingPathComponent("drive_c", isDirectory: true)
            let cache = root.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            // 7-Zip-style: the `<installerglob>` is not the literal downloaded name.
            let downloaded = cache.appendingPathComponent("7z920.exe")
            try Data("bin".utf8).write(to: downloaded)
            let environment = InstallPlanner.windowsEnvironment(driveC: driveC, userName: "tester")

            try expect(InstallPlanner.isGlob("7z92*.exe"), "a '*' pattern is a glob")
            try expect(!InstallPlanner.isGlob("7z920.exe"), "a concrete name is not a glob")
            try expect(
                InstallPlanner.commandLooksLikeFile("7z92*.exe", driveC: driveC, cache: cache, environment: environment),
                "an installer glob should resolve against the downloaded file"
            )
            try expectEqual(
                InstallPlanner.resolveLocalPath("7z92*.exe", driveC: driveC, cache: cache, environment: environment),
                downloaded.standardizedFileURL.path,
                "the glob resolves to the real downloaded file"
            )
            try expect(
                !InstallPlanner.commandLooksLikeFile("zz*.exe", driveC: driveC, cache: cache, environment: environment),
                "an unmatched glob is not a file"
            )
        }),

        TestCase(name: "windowsPathResolution", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-installer-\(UUID().uuidString)")
            let driveC = root.appendingPathComponent("drive_c", isDirectory: true)
            try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let environment = InstallPlanner.windowsEnvironment(driveC: driveC, userName: "tester")

            func expected(_ relative: String) -> String {
                driveC.appendingPathComponent(relative).standardizedFileURL.path
            }

            try expectEqual(
                InstallPlanner.resolveWindowsPath("C:\\Program Files\\App\\app.exe", driveC: driveC, environment: environment),
                expected("Program Files/App/app.exe")
            )
            try expectEqual(
                InstallPlanner.resolveWindowsPath("%ProgramFiles%\\App", driveC: driveC, environment: environment),
                expected("Program Files/App")
            )
            try expectEqual(
                InstallPlanner.resolveWindowsPath("%programfiles(x86)%\\App", driveC: driveC, environment: environment),
                expected("Program Files (x86)/App")
            )
            try expectEqual(
                InstallPlanner.resolveWindowsPath("%USERPROFILE%\\Desktop\\App.lnk", driveC: driveC, environment: environment),
                expected("users/tester/Desktop/App.lnk")
            )
            try expectEqual(
                InstallPlanner.resolveWindowsPath("%LOCALAPPDATA%\\App", driveC: driveC, environment: environment),
                expected("users/tester/AppData/Local/App")
            )
            try expectEqual(
                InstallPlanner.resolveWindowsPath("/tmp/absolute/path", driveC: driveC, environment: environment),
                "/tmp/absolute/path"
            )
            try expectEqual(
                InstallPlanner.resolveWindowsPath("C:\\", driveC: driveC, environment: environment).hasSuffix("drive_c"),
                true
            )
        }),

        TestCase(name: "localPathResolutionUsesCacheThenDriveC", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-installer-\(UUID().uuidString)")
            let driveC = root.appendingPathComponent("drive_c", isDirectory: true)
            let cache = root.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let downloaded = cache.appendingPathComponent("setup.exe")
            try Data("bin".utf8).write(to: downloaded)

            let environment = InstallPlanner.windowsEnvironment(driveC: driveC, userName: "tester")
            try expectEqual(
                InstallPlanner.resolveLocalPath("setup.exe", driveC: driveC, cache: cache, environment: environment),
                downloaded.standardizedFileURL.path
            )
            try expectEqual(
                InstallPlanner.resolveLocalPath("%ProgramFiles%\\App", driveC: driveC, cache: cache, environment: environment),
                driveC.appendingPathComponent("Program Files/App").standardizedFileURL.path
            )
            try expect(
                InstallPlanner.commandLooksLikeFile("setup.exe", driveC: driveC, cache: cache, environment: environment),
                "a downloaded file should run as a file"
            )
            try expect(
                !InstallPlanner.commandLooksLikeFile("cmd", driveC: driveC, cache: cache, environment: environment),
                "a Wine built-in should not run as a file"
            )
        }),

        TestCase(name: "registryArgumentVector", body: {
            try expectEqual(
                InstallPlanner.registryArguments(key: "HKCU\\Software\\Cork", name: "Foo", data: "Bar"),
                ["add", "HKCU\\Software\\Cork", "/v", "Foo", "/t", "REG_SZ", "/d", "Bar", "/f"]
            )
            try expectEqual(
                InstallPlanner.registryArguments(key: "HKLM\\K", name: "N", data: ""),
                ["add", "HKLM\\K", "/v", "N", "/t", "REG_SZ", "/d", "", "/f"]
            )
        }),

        TestCase(name: "planPreservesStepOrder", body: {
            let recipe = InstallRecipe(appID: "com.example.app", steps: [
                InstallStep(kind: .download, url: "https://example.com/app.zip"),
                InstallStep(kind: .setWindowsVersion, windowsVersion: "win10"),
                InstallStep(kind: .runInstaller, command: "setup.exe", arguments: ["/x"], silentArguments: ["/S"]),
                InstallStep(kind: .copyFiles, source: "files", destination: "%ProgramFiles%\\App"),
                InstallStep(kind: .createShortcut, destination: "C:\\Program Files\\App\\app.exe"),
                InstallStep(kind: .registry, registryKey: "HKCU\\Software\\X", registryName: "n", registryData: "d"),
            ])

            let planned = InstallPlanner.plan(recipe)
            try expectEqual(
                planned.map(\.kind),
                [.download, .setWindowsVersion, .runInstaller, .copyFiles, .createShortcut, .registry]
            )
            try expectEqual(planned.map(\.index), Array(0..<6))

            guard case .download(let url, let fileName, let extract) = planned[0].action else {
                throw TestFailure(description: "first action should be a download")
            }
            try expectEqual(url, "https://example.com/app.zip")
            try expectEqual(fileName, "app.zip")
            try expect(extract, "a .zip download should be extracted")
        }),

        TestCase(name: "planSkipsIncompleteSteps", body: {
            let recipe = InstallRecipe(appID: "x", steps: [
                InstallStep(kind: .download),
                InstallStep(kind: .runInstaller),
                InstallStep(kind: .runCommand),
                InstallStep(kind: .copyFiles, source: "only-source"),
                InstallStep(kind: .registry, registryKey: "HKLM\\K"),
                InstallStep(kind: .setWindowsVersion),
                InstallStep(kind: .createShortcut),
            ])
            for step in InstallPlanner.plan(recipe) {
                guard case .skip = step.action else {
                    throw TestFailure(description: "expected \(step.kind) to be skipped")
                }
            }
        }),

        TestCase(name: "runArgumentSelection", body: {
            let installer = InstallRecipe(appID: "x", steps: [
                InstallStep(kind: .runInstaller, command: "setup.exe", arguments: ["/interactive"], silentArguments: ["/S", "/norestart"]),
            ])
            guard case .run(let installerCommand, let installerArgs, _, let installerIsInstaller, let installerEnvironment) = InstallPlanner.plan(installer)[0].action else {
                throw TestFailure(description: "expected a run action")
            }
            try expectEqual(installerCommand, "setup.exe")
            try expectEqual(installerArgs, ["/S", "/norestart"])
            try expect(installerIsInstaller, "runInstaller should be flagged as an installer")
            try expect(installerEnvironment.isEmpty, "no environment overrides by default")

            let command = InstallRecipe(appID: "x", steps: [
                InstallStep(kind: .runCommand, command: "cmd", arguments: ["/c", "echo"], silentArguments: ["/quiet"]),
            ])
            guard case .run(let commandValue, let commandArgs, _, let commandIsInstaller, _) = InstallPlanner.plan(command)[0].action else {
                throw TestFailure(description: "expected a run action")
            }
            try expectEqual(commandValue, "cmd")
            try expectEqual(commandArgs, ["/c", "echo"])
            try expect(!commandIsInstaller, "runCommand should not be flagged as an installer")

            let fellBack = InstallRecipe(appID: "x", steps: [
                InstallStep(kind: .runCommand, command: "tool", silentArguments: ["/quiet"]),
            ])
            guard case .run(_, let fallbackArgs, _, _, _) = InstallPlanner.plan(fellBack)[0].action else {
                throw TestFailure(description: "expected a run action")
            }
            try expectEqual(fallbackArgs, ["/quiet"])
        }),

        TestCase(name: "shortcutSpecDefaults", body: {
            let step = InstallStep(
                kind: .createShortcut,
                arguments: ["--flag"],
                destination: "C:\\Program Files\\App\\app.exe"
            )
            guard let spec = ShortcutWriter.spec(for: step, appID: "com.example.app", userName: "tester") else {
                throw TestFailure(description: "spec should resolve from a destination")
            }
            try expectEqual(spec.name, "app")
            try expectEqual(spec.targetWindowsPath, "C:\\Program Files\\App\\app.exe")
            try expectEqual(spec.linkWindowsPath, "C:\\users\\tester\\Desktop\\app.lnk")
            try expectEqual(spec.workingDirectoryWindowsPath, "C:\\Program Files\\App")
            try expectEqual(spec.arguments, ["--flag"])

            let explicit = InstallStep(
                kind: .createShortcut,
                fileName: "My App",
                source: "C:\\menu\\My App.lnk",
                destination: "C:\\App\\app.exe"
            )
            guard let explicitSpec = ShortcutWriter.spec(for: explicit, appID: "x", userName: "tester") else {
                throw TestFailure(description: "spec should resolve")
            }
            try expectEqual(explicitSpec.name, "My App")
            try expectEqual(explicitSpec.linkWindowsPath, "C:\\menu\\My App.lnk")
        }),

        TestCase(name: "shortcutMinimalLinkStructure", body: {
            let spec = ShortcutSpec(
                name: "app",
                linkWindowsPath: "C:\\users\\tester\\Desktop\\app.lnk",
                targetWindowsPath: "C:\\App\\app.exe",
                workingDirectoryWindowsPath: "C:\\App",
                arguments: ["--flag"]
            )
            let data = ShortcutWriter.minimalLink(spec)
            try expect(data.count > 76, "link should contain a header and payload")

            let headerSize = [UInt8](data.prefix(4))
            try expectEqual(headerSize, [0x4C, 0x00, 0x00, 0x00])
            let clsid = [UInt8](data[4..<20])
            try expectEqual(clsid, [
                0x01, 0x14, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00,
                0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46,
            ])
            try expectEqual([UInt8](data.suffix(4)), [0, 0, 0, 0])
        }),

        TestCase(name: "shortcutVBSScript", body: {
            let step = InstallStep(kind: .createShortcut, arguments: ["--flag"], destination: "C:\\App\\app.exe")
            guard let spec = ShortcutWriter.spec(for: step, appID: "x", userName: "tester") else {
                throw TestFailure(description: "spec should resolve")
            }
            let script = ShortcutWriter.vbsScript(for: spec)
            try expect(script.contains("CreateObject(\"WScript.Shell\")"), "uses WScript.Shell")
            try expect(script.contains("C:\\App\\app.exe"), "sets the target")
            try expect(script.contains("link.Save"), "saves the shortcut")
        }),

        TestCase(name: "installerStatusAcceptance", body: {
            try expect(InstallPlanner.isSuccessfulInstallerStatus(0), "0 is success")
            try expect(InstallPlanner.isSuccessfulInstallerStatus(3010), "3010 means reboot required")
            try expect(InstallPlanner.isSuccessfulInstallerStatus(1641), "1641 means reboot initiated")
            try expect(!InstallPlanner.isSuccessfulInstallerStatus(1), "1 is a failure")
            try expect(!InstallPlanner.isSuccessfulInstallerStatus(1603), "1603 is a fatal install error")
        }),

        TestCase(name: "shortcutEnvironmentExpansion", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-installer-\(UUID().uuidString)")
            let driveC = root.appendingPathComponent("drive_c", isDirectory: true)
            try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let environment = InstallPlanner.windowsEnvironment(driveC: driveC, userName: "tester")
            try expectEqual(
                InstallPlanner.expandEnvironment(#"%StartMenu%\Programs\App.lnk"#, environment: environment),
                #"C:\users\tester\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\App.lnk"#
            )
            try expectEqual(
                InstallPlanner.resolveWindowsPath(#"%StartMenu%\Programs\App.lnk"#, driveC: driveC, environment: environment),
                driveC.appendingPathComponent("users/tester/AppData/Roaming/Microsoft/Windows/Start Menu/Programs/App.lnk").standardizedFileURL.path
            )
            try expectEqual(
                InstallPlanner.expandEnvironment(#"%ProgramFiles%\App\app.exe"#, environment: environment),
                #"C:\Program Files\App\app.exe"#
            )
        }),

        TestCase(name: "windowsPathContainment", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-installer-\(UUID().uuidString)")
            let driveC = root.appendingPathComponent("drive_c", isDirectory: true)
            let dosdevices = root.appendingPathComponent("dosdevices", isDirectory: true)
            try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createSymbolicLink(
                at: dosdevices.appendingPathComponent("z:"),
                withDestinationURL: URL(fileURLWithPath: "/")
            )

            let environment = InstallPlanner.windowsEnvironment(driveC: driveC, userName: "tester")
            let rootPrefix = driveC.standardizedFileURL.path

            for path in [
                #"\\server\share\app.exe"#,
                #"//server/share/app.exe"#,
                #"Z:\etc\passwd"#,
                #"D:\missing\app.exe"#,
                #"C:\..\..\escape.exe"#,
                #"..\..\escape.exe"#,
            ] {
                let resolved = InstallPlanner.resolveWindowsPath(path, driveC: driveC, environment: environment)
                try expect(
                    resolved == rootPrefix || resolved.hasPrefix(rootPrefix + "/"),
                    "\(path) escaped the prefix: \(resolved)"
                )
            }
        }),

        TestCase(name: "quotedArgumentSplitting", body: {
            try expectEqual(
                InstallPlanner.splitCommandLine(#"/S "/D=C:\Program Files\App" /norestart"#),
                ["/S", #"/D=C:\Program Files\App"#, "/norestart"]
            )
            try expectEqual(
                InstallPlanner.splitCommandLine(#"one 'two three' four"#),
                ["one", "'two", "three'", "four"],
                "single quotes are literal on Windows"
            )
            try expectEqual(
                InstallPlanner.splitCommandLine(#"empty "" arg"#),
                ["empty", "", "arg"]
            )
        }),

        TestCase(name: "runtimeGuardSkipsWithoutWine", body: {
            let manager = try RuntimeManager()
            guard manager.isWineReady else {
                print("      (no Wine runtime installed at \(manager.paths.runtimesDirectory.path), skipped)")
                return
            }
            let installation = try manager.requireWine()
            try expect(
                FileManager.default.isExecutableFile(atPath: installation.wineBinary.path),
                "a ready runtime should expose an executable wine binary"
            )
        }),
    ]
}
