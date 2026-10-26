import Foundation
import CorkKit

func archiveTests() -> [TestCase] {
    [
        TestCase(name: "validatesSafeEntries", body: {
            try Archive.validateEntries(["bin/wine", "lib/wine/x86_64-unix/winemetal.so", "./a"])
        }),
        TestCase(name: "rejectsAbsolutePaths", body: {
            try expectThrows(CorkError.self) {
                try Archive.validateEntries(["/etc/passwd"])
            }
        }),
        TestCase(name: "rejectsParentTraversal", body: {
            try expectThrows(CorkError.self) {
                try Archive.validateEntries(["a/../../evil"])
            }
        }),
        TestCase(name: "extractHonorsInstallRoot", body: {
            let fm = FileManager.default
            let base = fm.temporaryDirectory.appendingPathComponent("cork-archive-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: base) }

            let inner = base.appendingPathComponent("App.app/Contents/Resources/wine/bin")
            try fm.createDirectory(at: inner, withIntermediateDirectories: true)
            try Data("fake-wine".utf8).write(to: inner.appendingPathComponent("wine64"))

            let archive = base.appendingPathComponent("wine.tar")
            let create = try ProcessRunner.run(
                executable: "/usr/bin/tar",
                arguments: ["-cf", archive.path, "-C", base.path, "App.app"]
            )
            try expect(create.succeeded, create.stderr)

            let destination = base.appendingPathComponent("component")
            try Archive.extract(
                archive: archive,
                to: destination,
                installRoot: "App.app/Contents/Resources/wine",
                format: .tar
            )
            try expect(fm.fileExists(atPath: destination.appendingPathComponent("bin/wine64").path))
            try expect(!fm.fileExists(atPath: destination.appendingPathComponent("App.app").path))
        }),
        TestCase(name: "extractRejectsMissingInstallRoot", body: {
            let fm = FileManager.default
            let base = fm.temporaryDirectory.appendingPathComponent("cork-archive-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: base) }
            try fm.createDirectory(at: base.appendingPathComponent("only"), withIntermediateDirectories: true)
            let archive = base.appendingPathComponent("a.tar")
            _ = try ProcessRunner.run(executable: "/usr/bin/tar", arguments: ["-cf", archive.path, "-C", base.path, "only"])

            try expectThrows(CorkError.self) {
                try Archive.extract(
                    archive: archive,
                    to: base.appendingPathComponent("d"),
                    installRoot: "nope",
                    format: .tar
                )
            }
        }),
        TestCase(name: "rejectsSymlinkEscape", body: {
            try expectThrows(CorkError.self) {
                try Archive.validateEntries(["link/../../../etc/passwd"])
            }
        }),
        TestCase(name: "extractsZipArchives", body: {
            let fm = FileManager.default
            let base = fm.temporaryDirectory.appendingPathComponent("cork-zip-\(UUID().uuidString)")
            defer { try? fm.removeItem(at: base) }

            let inner = base.appendingPathComponent("App/Resources/wine/bin")
            try fm.createDirectory(at: inner, withIntermediateDirectories: true)
            try Data("fake-wine".utf8).write(to: inner.appendingPathComponent("wine64"))

            let archive = base.appendingPathComponent("app.zip")
            let create = try ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/zip"),
                arguments: ["-q", "-r", archive.path, "App"],
                currentDirectory: base
            )
            try expect(create.succeeded, create.stderr)
            let entries = try Archive.listEntries(archive: archive, format: .zip)
            try expect(entries.contains("App/Resources/wine/bin/wine64"), "zip listing should include the executable: \(entries)")

            let destination = base.appendingPathComponent("component")
            try Archive.extract(
                archive: archive,
                to: destination,
                installRoot: "App/Resources/wine",
                format: .zip
            )
            try expect(fm.fileExists(atPath: destination.appendingPathComponent("bin/wine64").path))
            try expect(!fm.fileExists(atPath: destination.appendingPathComponent("App").path))
        }),
    ]
}
