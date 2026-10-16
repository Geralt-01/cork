import CorkEngine
import Foundation

/// A small, self-contained CrossTie install fixture. Exercises every mapped
/// step kind, ordering, the reboot flag, installer-id indirection, 64-bit-only
/// downloads, quoted shortcut targets, and a metadata-only app.
///
/// Deliberately does NOT touch the real (multi-megabyte) `crossover.tie`.
private let installFixture = #"""
<?xml version="1.0" encoding="UTF-8"?>
<c4p>
  <highlightedapps>
    <highlightedapp appid="com.example.rich" platform="Mac"/>
  </highlightedapps>
  <applications>
    <app appid="com.example.rich" timestamp="2020-01-01T00:00:00-06:00">
      <cxversion product="cxoffice">20.0</cxversion>
      <name>Rich App</name>
      <name lang="de">Reiche App</name>
      <appprofile>
        <downloadurl>https://example.com/Setup.exe</downloadurl>
        <downloadurl64>https://example.com/Setup64.exe</downloadurl64>
        <downloadglob>Setup.exe</downloadglob>
      </appprofile>
      <installprofile>
        <predependency>com.example.dep</predependency>
        <installerwinver>winxp</installerwinver>
        <installerdlloverrides>foo=n;bar=b</installerdlloverrides>
        <installersilentoption>/S</installersilentoption>
        <installeroption>/sp-</installeroption>
        <preinstallregistry>
          <key>HKEY_CURRENT_USER\Software\X</key>
          <value><name>n</name><data>d</data></value>
        </preinstallregistry>
        <filestocopy>
          <glob>a.dll</glob>
          <dst>%WinDir%\a.dll</dst>
        </filestocopy>
        <postinstallregistry>
          <key>HKEY_CURRENT_USER\Software\Y</key>
          <value><name>m</name><data>e</data></value>
        </postinstallregistry>
        <postinstallreboot>true</postinstallreboot>
        <lnkfile>
          <shortcut>%StartMenu%\Programs\Rich App</shortcut>
          <target>%ProgramFiles%\Rich App\app.exe</target>
          <workdir>%ProgramFiles%\Rich App</workdir>
        </lnkfile>
      </installprofile>
    </app>
    <app appid="com.example.metadata">
      <name>Metadata Only</name>
      <appprofile><description>nothing to install here</description></appprofile>
      <installprofile/>
    </app>
    <app appid="com.example.dl64">
      <appprofile><downloadurl64>https://example.com/App64.msi</downloadurl64></appprofile>
    </app>
    <app appid="com.example.viaid">
      <appprofile><installerid>com.example.rich</installerid></appprofile>
    </app>
    <app appid="com.example.quoted">
      <appprofile><downloadurl>https://example.com/game.exe</downloadurl></appprofile>
      <installprofile>
        <postinstallreboot>false</postinstallreboot>
        <lnkfile>
          <shortcut>%StartMenu%\Games\Game</shortcut>
          <target>"C:\Games\Game.exe" +fullscreen 0</target>
        </lnkfile>
      </installprofile>
    </app>
  </applications>
</c4p>
"""#

/// Parses `xml` via a temporary file that is removed immediately afterwards.
private func makeInstallRecipes(_ xml: String) throws -> CrossTieInstallRecipes {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cork-install-\(UUID().uuidString).xml")
    try xml.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }
    return try CrossTieInstallRecipes(fileURL: url)
}

private func recipe(_ recipes: CrossTieInstallRecipes, _ id: String) throws -> InstallRecipe {
    guard let recipe = recipes.installRecipe(appID: id) else {
        throw TestFailure(description: "missing install recipe for \(id)")
    }
    return recipe
}

func installRecipeTests() -> [TestCase] {
    [
        TestCase(name: "installRecipeExtractsEveryStepKindInOrder", body: {
            let recipes = try makeInstallRecipes(installFixture)
            let recipe = try recipe(recipes, "com.example.rich")

            try expectEqual(
                recipe.steps.map(\.kind),
                [.download, .setWindowsVersion, .registry, .runInstaller, .registry, .copyFiles, .createShortcut],
                "steps should be ordered download → winver → pre-registry → installer → post-registry → copy → shortcut"
            )
            try expect(recipe.requiresReboot, "postinstallreboot=true")

            let download = recipe.steps[0]
            try expectEqual(download.url, "https://example.com/Setup.exe" as String?)
            try expectEqual(download.fileName, "Setup.exe" as String?)
            try expect(
                download.description?.contains("Setup64.exe") == true,
                "the 64-bit alternative should be noted in the download description"
            )

            try expectEqual(recipe.steps[1].windowsVersion, "winxp" as String?)

            let pre = recipe.steps[2]
            try expectEqual(pre.registryKey, #"HKEY_CURRENT_USER\Software\X"# as String?)
            try expectEqual(pre.registryName, "n" as String?)
            try expectEqual(pre.registryData, "d" as String?)

            let installer = recipe.steps[3]
            try expectEqual(installer.command, "Setup.exe" as String?)
            try expectEqual(installer.silentArguments, ["/S"])
            try expectEqual(installer.arguments, ["/sp-"])
            try expect(installer.description?.contains("com.example.dep") == true, "dependency noted")

            let post = recipe.steps[4]
            try expectEqual(post.registryKey, #"HKEY_CURRENT_USER\Software\Y"# as String?)
            try expectEqual(post.registryName, "m" as String?)
            try expectEqual(post.registryData, "e" as String?)

            let copy = recipe.steps[5]
            try expectEqual(copy.source, "a.dll" as String?)
            try expectEqual(copy.destination, #"%WinDir%\a.dll"# as String?)

            let shortcut = recipe.steps[6]
            try expectEqual(shortcut.destination, #"%ProgramFiles%\Rich App\app.exe"# as String?, "shortcut target")
            try expectEqual(shortcut.fileName, "Rich App" as String?)
            try expectEqual(shortcut.source, #"%StartMenu%\Programs\Rich App.lnk"# as String?, "the .lnk link path")
            try expectEqual(shortcut.workingDirectory, #"%ProgramFiles%\Rich App"# as String?)
        }),

        TestCase(name: "installRecipeExtractsDllOverrides", body: {
            let recipes = try makeInstallRecipes(installFixture)
            let recipe = try recipe(recipes, "com.example.rich")
            try expectEqual(recipe.dllOverrides, ["foo=n", "bar=b"], "installerdlloverrides are split on ';'")
        }),

        TestCase(name: "installRecipeReturnsNilForMetadataOnlyAndUnknownApps", body: {
            let recipes = try makeInstallRecipes(installFixture)
            try expect(recipes.installRecipe(appID: "com.example.metadata") == nil, "self-closing profile / metadata only")
            try expect(recipes.installRecipe(appID: "com.example.absent") == nil, "unknown app id")
        }),

        TestCase(name: "installRecipeMapsDownloadUrl64AndDerivesInstaller", body: {
            let recipes = try makeInstallRecipes(installFixture)
            let recipe = try recipe(recipes, "com.example.dl64")
            try expectEqual(recipe.steps.map(\.kind), [.download, .runInstaller])
            try expectEqual(recipe.steps[0].url, "https://example.com/App64.msi" as String?)
            try expectEqual(recipe.steps[0].fileName, "App64.msi" as String?)
            try expectEqual(recipe.steps[1].command, "App64.msi" as String?)
            try expect(!recipe.requiresReboot)
        }),

        TestCase(name: "installRecipeFollowsInstallerIDReference", body: {
            let recipes = try makeInstallRecipes(installFixture)
            let recipe = try recipe(recipes, "com.example.viaid")
            try expectEqual(recipe.appID, "com.example.viaid", "the requested id is preserved")
            try expect(recipe.steps.contains { $0.kind == .runInstaller }, "inherits the referenced installer")
            try expect(recipe.steps.contains { $0.kind == .createShortcut }, "inherits referenced steps")
            try expect(recipe.requiresReboot, "inherits the referenced reboot flag")
        }),

        TestCase(name: "installRecipeSplitsQuotedShortcutTarget", body: {
            let recipes = try makeInstallRecipes(installFixture)
            let recipe = try recipe(recipes, "com.example.quoted")
            try expectEqual(recipe.steps.map(\.kind), [.download, .runInstaller, .createShortcut])
            guard let shortcut = recipe.steps.last else { throw TestFailure(description: "expected a shortcut step") }
            try expectEqual(shortcut.destination, #"C:\Games\Game.exe"# as String?, "quoted target is unquoted")
            try expectEqual(shortcut.arguments, ["+fullscreen", "0"], "trailing arguments are split out")
            try expectEqual(shortcut.fileName, "Game" as String?)
            try expect(!recipe.requiresReboot, "postinstallreboot=false")
        }),

        TestCase(name: "installRecipeMalformedXMLThrows", body: {
            try expectThrows(CrossTieParserError.self, "unterminated XML should throw") {
                _ = try makeInstallRecipes("<?xml version=\"1.0\"?><c4p><applications><app appid=\"x\">")
            }
        }),
    ]
}
