import CorkEngine
import CorkKit
import Foundation

/// Tests for the winetricks-style dependency catalog and its pure step model.
///
/// These run with no network access and no Wine runtime: they only exercise the
/// built-in catalog, the id lookups and ``DependencyPlanner``'s translation of
/// declarative steps into concrete Wine commands/arguments.
func depsTests() -> [TestCase] {
    [
        TestCase(name: "depsCatalogIsNonEmptySortedAndUnique", body: {
            let manager = DependencyManager()
            let components = manager.components()
            try expect(!components.isEmpty, "the built-in catalog must not be empty")

            let ids = components.map(\.id)
            try expectEqual(Set(ids).count, ids.count, "component ids must be unique")
            try expectEqual(ids, ids.sorted(), "components() must be sorted by id")

            for component in components {
                try expect(!component.id.isEmpty, "every component needs an id")
                try expect(!component.name.isEmpty, "\(component.id) needs a name")
                try expect(!component.category.isEmpty, "\(component.id) needs a category")
                try expect(
                    component.summary?.isEmpty == false,
                    "\(component.id) should honestly summarise what it does"
                )
                try expect(!component.verbs.isEmpty, "\(component.id) should list its steps as verbs")
            }
        }),

        TestCase(name: "depsCatalogShipsTheCuratedSet", body: {
            let manager = DependencyManager()
            let ids = Set(manager.components().map(\.id))
            let expected: Set<String> = [
                "vcrun6", "vcrun2015", "vcrun2017", "vcrun2019", "vcrun2022",
                "dotnet48", "d3dx9", "d3dx11", "xact", "msxml6",
                "riched20", "corefonts", "directplay", "gdiplus",
            ]
            try expect(expected.isSubset(of: ids), "missing: \(expected.subtracting(ids).sorted())")
        }),

        TestCase(name: "depsComponentLookupIsCaseInsensitive", body: {
            let manager = DependencyManager()
            try expectEqual(manager.component(id: "vcrun2019")?.id, "vcrun2019" as String?)
            try expectEqual(manager.component(id: "VCRUN2019")?.id, "vcrun2019" as String?)
            try expectEqual(manager.component(id: "  DotNet48  ")?.id, "dotnet48" as String?)
            try expect(manager.component(id: "definitely-not-a-component") == nil, "unknown id")
            try expect(manager.component(id: "") == nil, "empty id")
        }),

        TestCase(name: "depsDefinitionLookupAndUnknownHandling", body: {
            let manager = DependencyManager()
            guard let definition = manager.definition(id: "d3dx9") else {
                throw TestFailure(description: "d3dx9 definition not found")
            }
            try expectEqual(definition.component.id, "d3dx9")
            try expect(!definition.steps.isEmpty, "a definition must carry steps")
            try expect(manager.definition(id: "nope") == nil, "unknown definition")
        }),

        TestCase(name: "depsPlannerBuildsRegistryArguments", body: {
            let step = DependencyStep.registry(
                key: #"HKCU\Software\Wine\DllOverrides"#,
                name: "mscoree",
                data: "native"
            )
            let action = DependencyPlanner.action(for: step)
            try expectEqual(
                action,
                DependencyPlanner.Action.registry(
                    executable: "reg",
                    arguments: [
                        "add", #"HKCU\Software\Wine\DllOverrides"#,
                        "/v", "mscoree", "/t", "REG_SZ", "/d", "native", "/f",
                    ]
                )
            )
            // Must match the executor's shared helper exactly.
            try expectEqual(
                DependencyPlanner.action(for: step),
                DependencyPlanner.Action.registry(
                    executable: "reg",
                    arguments: InstallPlanner.registryArguments(
                        key: #"HKCU\Software\Wine\DllOverrides"#,
                        name: "mscoree",
                        data: "native"
                    )
                )
            )
        }),

        TestCase(name: "depsPlannerResolvesEveryStepKind", body: {
            try expectEqual(
                DependencyPlanner.action(for: .setWindowsVersion("win7")),
                .setWindowsVersion("win7")
            )
            try expectEqual(
                DependencyPlanner.action(for: .download(url: "https://example.com/a.exe", fileName: "a.exe")),
                .download(url: "https://example.com/a.exe", fileName: "a.exe")
            )
            try expectEqual(
                DependencyPlanner.action(for: .createDirectory(#"C:\cork\x"#)),
                .createDirectory(#"C:\cork\x"#)
            )
            try expectEqual(
                DependencyPlanner.action(for: .runInstaller(command: "a.exe", arguments: ["/q"])),
                .runInstaller(executable: "a.exe", arguments: ["/q"])
            )
            try expectEqual(
                DependencyPlanner.action(for: .runCommand(command: "b.exe", arguments: ["/Q"])),
                .runCommand(executable: "b.exe", arguments: ["/Q"])
            )
            try expectEqual(
                DependencyPlanner.action(for: .copyFile(source: "a.dll", destination: #"%WinDir%\a.dll"#)),
                .copyFile(source: "a.dll", destination: #"%WinDir%\a.dll"#)
            )
            try expectEqual(
                DependencyPlanner.action(for: .manual("do it yourself")),
                .manual(reason: "do it yourself")
            )
        }),

        TestCase(name: "depsPlannerPlansDefinitionInOrder", body: {
            guard let definition = DependencyManager().definition(id: "vcrun2019") else {
                throw TestFailure(description: "vcrun2019 definition not found")
            }
            let plan = DependencyPlanner.plan(definition)
            try expectEqual(plan.count, definition.steps.count, "one action per step, order preserved")
            for (action, step) in zip(plan, definition.steps) {
                try expectEqual(action, DependencyPlanner.action(for: step))
            }
        }),

        TestCase(name: "depsDownloadStepsAreSelfConsistent", body: {
            let manager = DependencyManager()
            for component in manager.components() where component.requiresDownload {
                guard let definition = manager.definition(id: component.id) else {
                    throw TestFailure(description: "missing definition for \(component.id)")
                }
                let downloads = definition.steps.compactMap { step -> (url: String, fileName: String)? in
                    if case let .download(url, fileName) = step { return (url, fileName) }
                    return nil
                }
                try expect(!downloads.isEmpty, "\(component.id) claims a download but has no download step")
                for download in downloads {
                    try expect(
                        download.url.hasPrefix("https://"),
                        "\(component.id): downloads must be https (\(download.url))"
                    )
                    try expect(
                        download.fileName == (download.fileName as NSString).lastPathComponent,
                        "\(component.id): file name must be a bare basename (\(download.fileName))"
                    )
                    try expect(
                        !download.fileName.contains("/") && !download.fileName.contains(":"),
                        "\(component.id): file name must not be a path"
                    )
                }
            }
        }),

        TestCase(name: "depsManualComponentsAreHonest", body: {
            let manager = DependencyManager()
            for id in ["vcrun6", "riched20", "corefonts", "gdiplus"] {
                guard let definition = manager.definition(id: id) else {
                    throw TestFailure(description: "missing definition for \(id)")
                }
                try expect(
                    !definition.component.requiresDownload,
                    "\(id) is manual, so it must not claim a Cork download"
                )
                let hasManualStep = definition.steps.contains {
                    if case .manual = $0 { return true }
                    return false
                }
                try expect(hasManualStep, "\(id) must carry an explicit manual step")
            }
        }),

        TestCase(name: "depsDotnet48SetsWindowsVersionAndNeedsReboot", body: {
            guard let definition = DependencyManager().definition(id: "dotnet48") else {
                throw TestFailure(description: "dotnet48 missing")
            }
            try expect(definition.requiresReboot, "dotnet48 needs a reboot")
            try expect(
                definition.steps.contains(.setWindowsVersion("win7")),
                "dotnet48 must set the prefix to Windows 7 first"
            )
            let actions = DependencyPlanner.plan(definition)
            try expectEqual(actions.first, .setWindowsVersion("win7"), "setWindowsVersion comes first")
            try expect(
                actions.contains(.runInstaller(
                    executable: "ndp48-x86-x64-allos-enu.exe",
                    arguments: ["/sfxlang:1027", "/q", "/norestart"]
                )),
                "dotnet48 must run the offline installer silently"
            )
        }),

        TestCase(name: "depsDirectXComponentsShareRedistAndDXSetup", body: {
            let manager = DependencyManager()
            for id in ["d3dx9", "d3dx11", "xact"] {
                guard let definition = manager.definition(id: id) else {
                    throw TestFailure(description: "missing definition for \(id)")
                }
                let actions = DependencyPlanner.plan(definition)
                try expect(
                    actions.contains { action in
                        if case .runInstaller(let executable, let arguments) = action {
                            return executable.hasSuffix(#"DXSETUP.exe"#) && arguments == ["/silent"]
                        }
                        return false
                    },
                    "\(id) should run DXSETUP.exe /silent"
                )
                try expect(
                    actions.contains { action in
                        if case .createDirectory(let directory) = action {
                            return directory.hasPrefix(#"C:\cork\"#)
                        }
                        return false
                    },
                    "\(id) should create its extraction directory first"
                )
            }
        }),

        TestCase(name: "depsDefinitionIsCodableRoundTrip", body: {
            guard let original = DependencyManager().definition(id: "d3dx9") else {
                throw TestFailure(description: "d3dx9 missing")
            }
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(DependencyDefinition.self, from: data)
            try expectEqual(decoded, original, "the definition model must round-trip through JSON")
        }),

        TestCase(name: "depsCategoriesAreNonEmptyAndSorted", body: {
            let categories = DependencyCatalog.categories()
            try expect(!categories.isEmpty, "at least one category")
            try expectEqual(categories, categories.sorted(), "categories are sorted")
            let componentCategories = Set(DependencyManager().components().map(\.category))
            try expectEqual(Set(categories), componentCategories, "every component category is reported")
        }),
    ]
}
