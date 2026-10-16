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
        <preinstallenvironment>
          <name>FOO</name>
          <value>bar</value>
        </preinstallenvironment>
        <installerenvironment>
          <name>BAZ</name>
          <value>qux</value>
        </installerenvironment>
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

/// A second fixture for the install-cd track: multi-`<installerid>` chains
/// (ordering, dedupe, cycle protection), CD/media installs (embedded component
/// installers + the un-named main setup), and 32/64-bit download pairs.
private let installChainFixture = #"""
<?xml version="1.0" encoding="UTF-8"?>
<c4p>
  <applications>
    <app appid="com.example.chain.host">
      <appprofile>
        <downloadurl>https://example.com/host.exe</downloadurl>
        <installerid>com.example.chain.dep1</installerid>
        <installerid>com.example.chain.dep2</installerid>
        <installerid>com.example.chain.dep1</installerid>
      </appprofile>
      <installprofile>
        <preinstallregistry>
          <key>HKEY_CURRENT_USER\Software\Host</key>
          <value><name>h</name><data>1</data></value>
        </preinstallregistry>
      </installprofile>
    </app>
    <app appid="com.example.chain.dep1">
      <appprofile>
        <downloadurl>https://example.com/dep1.exe</downloadurl>
        <installerid>com.example.chain.dep2</installerid>
      </appprofile>
    </app>
    <app appid="com.example.chain.dep2">
      <appprofile>
        <downloadurl>https://example.com/dep2.exe</downloadurl>
        <installerid>com.example.chain.host</installerid>
      </appprofile>
    </app>

    <app appid="com.example.media">
      <appprofile><description>CD app</description></appprofile>
      <installprofile>
        <preinstallregistry>
          <key>HKEY_CURRENT_USER\Software\Media</key>
          <value><name>m</name><data>2</data></value>
        </preinstallregistry>
      </installprofile>
      <installprofile appid="com.example.media.component">
        <localinstallerglob>media/COMP/SETUP.EXE</localinstallerglob>
      </installprofile>
      <cdprofile>
        <cdglob>
          <glob>autorun.inf</glob>
          <pattern>ProductCode={CD}</pattern>
        </cdglob>
      </cdprofile>
    </app>

    <app appid="com.example.media.derivable">
      <installprofile>
        <installerglob>disc/setup.exe</installerglob>
      </installprofile>
      <cdprofile>
        <cdglob><glob>setup.ini</glob><pattern>X</pattern></cdglob>
      </cdprofile>
    </app>

    <app appid="com.example.bothurls">
      <appprofile>
        <downloadurl>https://example.com/App32.exe</downloadurl>
        <downloadurl64>https://example.com/App64.exe</downloadurl64>
      </appprofile>
    </app>
  </applications>
</c4p>
"""#

/// A 7-Zip-style catalog: one `appid` with two `<cxversion>` records, each
/// pairing a *versioned* download URL with its own installer glob, plus a
/// glob-valued `<downloadglob>` on the newer record. Cork must keep the
/// download URL and the installer glob from the *same* record.
private let installTwoVersionFixture = #"""
<?xml version="1.0" encoding="UTF-8"?>
<c4p>
  <applications>
    <app appid="com.example.twover" timestamp="2020-01-01T00:00:00-06:00">
      <cxversion product="cxoffice">9.0</cxversion>
      <name>Two Ver</name>
      <appprofile>
        <downloadurl>https://example.com/files/4.65/app465.exe/download</downloadurl>
      </appprofile>
      <installprofile><installerglob>app46*.exe</installerglob></installprofile>
    </app>
    <app appid="com.example.twover" timestamp="2022-01-01T00:00:00-06:00">
      <cxversion product="cxoffice">10.0</cxversion>
      <name>Two Ver</name>
      <appprofile>
        <downloadurl>https://example.com/files/9.20/app920.exe/download</downloadurl>
        <downloadglob>app*.exe</downloadglob>
      </appprofile>
      <installprofile><installerglob>app92*.exe</installerglob></installprofile>
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
            try expectEqual(recipe.steps[0].downloadURL64, nil, "no separate alternative when only the 64-bit URL exists")
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

        TestCase(name: "installRecipeResolvesAllInstallerIDsInOrderWithCycleProtection", body: {
            let recipes = try makeInstallRecipes(installChainFixture)
            let recipe = try recipe(recipes, "com.example.chain.host")

            // dep2 → dep1 → host, with the host's own registry preamble placed
            // after dependencies but before the host's own installer.
            try expectEqual(
                recipe.steps.map(\.kind),
                [.download, .runInstaller, .download, .runInstaller, .registry, .download, .runInstaller],
                "dependencies' steps come first, then the host's own preamble, then the host's run step"
            )
            try expectEqual(
                recipe.steps.compactMap(\.url),
                [
                    "https://example.com/dep2.exe",
                    "https://example.com/dep1.exe",
                    "https://example.com/host.exe",
                ],
                "every installer id is resolved, in dependency order"
            )
            try expectEqual(recipe.steps[4].registryKey, #"HKEY_CURRENT_USER\Software\Host"# as String?)

            try expectEqual(
                recipe.steps.filter { $0.url == "https://example.com/dep1.exe" }.count,
                1,
                "a duplicated installer id is expanded once"
            )
            try expectEqual(
                recipe.steps.filter { $0.url == "https://example.com/dep2.exe" }.count,
                1,
                "a shared/cyclic dependency is expanded once"
            )
        }),

        TestCase(name: "installRecipeSurfacesEnvironmentAndPredependencies", body: {
            let recipes = try makeInstallRecipes(installFixture)
            let recipe = try recipe(recipes, "com.example.rich")
            try expectEqual(recipe.predependencies, ["com.example.dep"], "predependency is a first-class field")
            guard let installer = recipe.steps.first(where: { $0.kind == .runInstaller }) else {
                throw TestFailure(description: "expected a runInstaller step")
            }
            try expectEqual(
                installer.environment,
                ["FOO": "bar", "BAZ": "qux"],
                "pre/install environment is surfaced on the run step"
            )
        }),

        TestCase(name: "installRecipeRepresentsBothDownloadURLs", body: {
            let recipes = try makeInstallRecipes(installChainFixture)
            let recipe = try recipe(recipes, "com.example.bothurls")
            try expectEqual(
                recipe.steps.map(\.kind),
                [.download, .runInstaller],
                "documented single-step rule: one download (plus the derived run step), never both URLs"
            )
            let download = recipe.steps[0]
            try expectEqual(download.url, "https://example.com/App32.exe" as String?)
            try expectEqual(download.downloadURL64, "https://example.com/App64.exe" as String?, "the 64-bit URL is preserved")
            try expectEqual(download.fileName, "App32.exe" as String?)
        }),

        TestCase(name: "installRecipeMarksCDOnlyMainSetupAsRequiringMedia", body: {
            let recipes = try makeInstallRecipes(installChainFixture)
            let recipe = try recipe(recipes, "com.example.media")

            try expectEqual(
                recipe.steps.map(\.kind),
                [.registry, .runInstaller, .runInstaller],
                "pre-registry, then the component installer, then the un-named main setup"
            )

            let component = recipe.steps[1]
            try expectEqual(component.command, "SETUP.EXE" as String?, "the embedded component installer is runnable")
            try expect(
                component.description?.contains("com.example.media.component") == true,
                "the component glob is attributed to its own app, not the host"
            )
            try expect(component.requiresMedia, "a component shipped on the CD needs the disc")
            try expectEqual(component.mediaPath, "autorun.inf" as String?)

            let mainSetup = recipe.steps[2]
            try expectEqual(mainSetup.command, nil, "the un-named main setup is not guessed")
            try expect(mainSetup.requiresMedia, "the main setup requires the installation media")
            try expectEqual(mainSetup.mediaPath, "autorun.inf" as String?)
            try expect(
                mainSetup.description?.contains("installation media required") == true,
                "the gap is worded explicitly, not silently dropped"
            )
        }),

        TestCase(name: "installRecipeUsesDerivableCDInstaller", body: {
            let recipes = try makeInstallRecipes(installChainFixture)
            let recipe = try recipe(recipes, "com.example.media.derivable")
            try expectEqual(recipe.steps.map(\.kind), [.runInstaller], "no placeholder when the setup is named")
            try expectEqual(recipe.steps[0].command, "setup.exe" as String?)
            try expect(recipe.steps[0].requiresMedia, "a CD installer still needs the disc")
            try expectEqual(recipe.steps[0].mediaPath, "setup.ini" as String?)
        }),

        TestCase(name: "installRecipeMalformedXMLThrows", body: {
            try expectThrows(CrossTieParserError.self, "unterminated XML should throw") {
                _ = try makeInstallRecipes("<?xml version=\"1.0\"?><c4p><applications><app appid=\"x\">")
            }
        }),

        TestCase(name: "installRecipeKeepsDownloadAndInstallerGlobCoherent", body: {
            // Regression: two records for one appid must not be cross-mixed —
            // a download URL from one version paired with the installer glob of
            // another (7-Zip downloaded 7z920.exe but ran 7z46*.exe).
            let recipes = try makeInstallRecipes(installTwoVersionFixture)
            let recipe = try recipe(recipes, "com.example.twover")
            try expectEqual(recipe.steps.map(\.kind), [.download, .runInstaller])

            let download = recipe.steps[0]
            try expectEqual(
                download.url,
                "https://example.com/files/9.20/app920.exe/download" as String?,
                "the newest record's download url wins"
            )
            try expectEqual(
                download.fileName,
                "app920.exe" as String?,
                "a glob-valued <downloadglob> is not used as a literal file name; the URL name is"
            )

            let installer = recipe.steps[1]
            try expectEqual(
                installer.command,
                "app92*.exe" as String?,
                "the installer glob comes from the same record as the download url"
            )
        }),
    ]
}
