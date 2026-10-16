import CorkEngine
import CorkKit
import Foundation

/// Tests for file associations. Owned by the associations track.
///
/// These never require a Wine runtime: `appliesRegistry: false` keeps the tests
/// to the Cork-owned JSON file, and `registerInBundle` only touches a temp
/// `.app` whose `Info.plist` we create.
func assocTests() -> [TestCase] {
    /// A throwaway Cork home + bottle directory, no Wine required.
    func makeStore(registry: Bool = false) throws -> (AssociationStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cork-assoc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let paths = CorkPaths(root: root)
        return (AssociationStore(paths: paths, appliesRegistry: registry), root)
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

    /// Builds a minimal `<name>.app/Contents/Info.plist`.
    func makeBundle(in root: URL, name: String = "Test") throws -> URL {
        let bundleURL = root.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleName": name,
            "CFBundleIdentifier": "tools.cork.app.test",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return bundleURL
    }

    let samples = [
        AssociationEntry(
            fileExtension: ".psd",
            progID: "Photoshop.Image.12",
            friendlyName: "Photoshop Image",
            executable: "C:\\Program Files\\Adobe\\Photoshop.exe",
            arguments: []
        ),
        AssociationEntry(
            fileExtension: ".txt",
            progID: "Cork.Notepad",
            executable: "C:\\Windows\\notepad.exe"
        ),
    ]

    return [
        TestCase(name: "setReadRoundTrip", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            try store.set(samples[0], bottle: "Assoc")
            let entries = try store.read(bottle: "Assoc")
            try expectEqual(entries, [samples[0]])
            try expect(FileManager.default.fileExists(
                atPath: store.fileURL(bottle: "Assoc").path
            ), "association file not written")
        }),

        TestCase(name: "setReplacesExistingExtension", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            try store.set(samples[0], bottle: "Assoc")
            var replacement = samples[0]
            replacement.executable = "C:\\Other\\Editor.exe"
            replacement.progID = "Other.Editor"
            try store.set(replacement, bottle: "Assoc")

            let entries = try store.read(bottle: "Assoc")
            try expectEqual(entries.count, 1)
            try expectEqual(entries.first?.executable, "C:\\Other\\Editor.exe")
            try expectEqual(entries.first?.progID, "Other.Editor")
        }),

        TestCase(name: "removeAssociation", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            try store.write(bottle: "Assoc", entries: samples)
            try store.remove(fileExtension: ".psd", bottle: "Assoc")
            let entries = try store.read(bottle: "Assoc")
            try expectEqual(entries.map(\.fileExtension), [".txt"])
        }),

        TestCase(name: "removeMissingExtensionIsNoOp", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            try store.write(bottle: "Assoc", entries: samples)
            try store.remove(fileExtension: ".nope", bottle: "Assoc")
            try expectEqual(try store.read(bottle: "Assoc").count, 2)
        }),

        TestCase(name: "writeSortsAndDedups", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            let messy = [
                AssociationEntry(fileExtension: "txt", progID: "A", executable: "C:\\a.exe"),
                AssociationEntry(fileExtension: ".PSD", progID: "Old", friendlyName: "Old", executable: "C:\\1.exe"),
                AssociationEntry(fileExtension: "psd", progID: "New", friendlyName: "New", executable: "C:\\2.exe"),
            ]
            try store.write(bottle: "Assoc", entries: messy)
            let entries = try store.read(bottle: "Assoc")

            try expectEqual(entries.map(\.fileExtension), [".psd", ".txt"])
            // Last write wins for a duplicated extension, extension canonicalised.
            try expectEqual(entries.first?.progID, "New")
        }),

        TestCase(name: "missingFileReadsEmpty", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }
            try expectEqual(try store.read(bottle: "NoSuchBottle"), [])
        }),

        TestCase(name: "corruptJSONReadsEmpty", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            let url = store.fileURL(bottle: "Assoc")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("{ this is not json".utf8).write(to: url)
            try expectEqual(try store.read(bottle: "Assoc"), [])

            // And a valid-JSON-but-wrong-shape file is also tolerated.
            try Data("[1, 2, 3]".utf8).write(to: url)
            try expectEqual(try store.read(bottle: "Assoc"), [])
        }),

        TestCase(name: "registryCommandsAreWellFormed", body: {
            // Pure transformation; no runtime or bottle needed.
            func value(in command: [String]) -> String? {
                guard let index = command.firstIndex(of: "/d"), index + 1 < command.count else { return nil }
                return command[index + 1]
            }

            let commands = AssociationRegistry.commands(for: samples[0])
            try expectEqual(commands.count, 4)

            let progKey = #"HKCU\Software\Classes\Photoshop.Image.12"#
            try expectEqual(commands[0][0], "add")
            try expectEqual(commands[0][1], progKey)
            try expectEqual(commands[0].contains("FriendlyTypeName"), false)
            // default value carries the friendly name
            try expectEqual(value(in: commands[0]), "Photoshop Image")

            try expectEqual(commands[1][1], progKey)
            try expectEqual(commands[1].contains("FriendlyTypeName"), true)

            try expectEqual(commands[2][1], progKey + #"\shell\open\command"#)
            try expectEqual(value(in: commands[2]), "\"C:\\Program Files\\Adobe\\Photoshop.exe\" \"%1\"")

            try expectEqual(commands[3][1], #"HKCU\Software\Classes\.psd"#)
            try expectEqual(value(in: commands[3]), "Photoshop.Image.12")

            // Without a friendly name there is no FriendyTypeName value.
            let plain = AssociationRegistry.commands(for: samples[1])
            try expectEqual(plain.count, 3)
            try expect(plain.allSatisfy { !$0.contains("FriendlyTypeName") },
                           "unexpected FriendlyTypeName value")
            try expectEqual(value(in: plain[0]), "Cork.Notepad")

            try expect(AssociationRegistry.commandLines(for: samples[0]).count == 4,
                       "expected four printable command lines")
        }),

        TestCase(name: "registerInBundleWritesDocumentTypes", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            try store.write(bottle: "Assoc", entries: samples)
            let bundleURL = try makeBundle(in: root)
            let registered = try store.registerInBundle(bundleURL, bottle: "Assoc")

            try expectEqual(registered, [".psd", ".txt"])
            let plist = try readPlist(bundleURL.appendingPathComponent("Contents/Info.plist"))

            let docs = (plist["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []
            try expectEqual(docs.count, 2)
            try expectEqual(docs.first?["CFBundleTypeExtensions"] as? [String], ["psd"])
            try expectEqual(docs.first?["LSItemContentTypes"] as? [String],
                            ["tools.cork.assoc.photoshop-image-12"])

            let utis = (plist["UTExportedTypeDeclarations"] as? [[String: Any]]) ?? []
            try expectEqual(utis.count, 2)
            let firstUTI = utis.first { ($0["UTTypeIdentifier"] as? String) == "tools.cork.assoc.photoshop-image-12" }
            try expect(firstUTI != nil, "missing UTI declaration")
            try expectEqual(firstUTI?["UTTypeConformsTo"] as? [String], ["public.data"])
            let tags = (firstUTI?["UTTypeTagSpecification"] as? [String: Any])?["public.filename-extension"] as? [String]
            try expectEqual(tags, ["psd"])
        }),

        TestCase(name: "registerInBundleIsIdempotentAndPreservesOthers", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            let bundleURL = try makeBundle(in: root)
            let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")

            // Pre-existing, unrelated document type must survive.
            var plist = try readPlist(infoURL)
            plist["CFBundleDocumentTypes"] = [[
                "CFBundleTypeExtensions": ["foo"],
                "CFBundleTypeName": "Foo",
                "CFBundleTypeRole": "Viewer",
            ]]
            let seeded = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try seeded.write(to: infoURL)

            try store.write(bottle: "Assoc", entries: samples)
            _ = try store.registerInBundle(bundleURL, bottle: "Assoc")
            _ = try store.registerInBundle(bundleURL, bottle: "Assoc")

            let after = try readPlist(infoURL)
            let docs = (after["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []
            try expectEqual(docs.count, 3, "expected unrelated + 2 associated entries, no duplicates")
            let extensions = docs.compactMap { ($0["CFBundleTypeExtensions"] as? [String])?.first }
            try expect(extensions.contains("foo"), "unrelated doc type was dropped")
            try expectEqual(Set(extensions), ["foo", "psd", "txt"])

            let utis = (after["UTExportedTypeDeclarations"] as? [[String: Any]]) ?? []
            try expectEqual(utis.count, 2, "UTI declarations duplicated")
        }),

        TestCase(name: "registerInBundleThrowsOnUnreadablePlist", body: {
            let (store, root) = try makeStore()
            defer { try? FileManager.default.removeItem(at: root) }

            try store.set(samples[0], bottle: "Assoc")
            let emptyBundle = root.appendingPathComponent("Empty.app", isDirectory: true)
            try expectThrows(CorkError.self, "missing Info.plist") {
                _ = try store.registerInBundle(emptyBundle, bottle: "Assoc")
            }
        }),

        TestCase(name: "setBestEffortWithoutRuntimePersists", body: {
            // Registry application enabled but no runtime/bottle on disk: the
            // change must still be persisted and must not throw.
            let (store, root) = try makeStore(registry: true)
            defer { try? FileManager.default.removeItem(at: root) }

            try store.set(samples[0], bottle: "Assoc")
            try expectEqual(try store.read(bottle: "Assoc"), [samples[0]])
        }),
    ]
}
