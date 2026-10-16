import CorkEngine
import Foundation

/// A tiny, self-contained CrossTie (`c4p`) fixture. Deliberately exercises the
/// tricky bits: duplicate `appid` records across `<cxversion>`s, localized and
/// untagged names/descriptions, competing medals, installer metadata, and a
/// self-closing `<installprofile/>`.
private let crossTieFixture = """
<?xml version="1.0" encoding="UTF-8"?>
<c4p>
  <highlightedapps>
    <highlightedapp appid="com.example.word" platform="Mac"/>
  </highlightedapps>
  <revokelist>
    <revokeapp appid="com.example.gone" first="2018-01-01T00:00:00-06:00" last="2079-12-31T00:00:00-06:00"/>
  </revokelist>
  <app appid="com.example.word" timestamp="2020-01-01T00:00:00-06:00">
    <cxversion product="cxoffice">9.0</cxversion>
    <name>Example Word</name>
    <name lang="en">Example Word</name>
    <name lang="de">Beispiel Word</name>
    <appprofile>
      <description>An example word processor.</description>
      <description lang="en">An example word processor.</description>
      <description lang="de">Ein Beispiel-Textverarbeitungsprogramm.</description>
      <medal rating="4" platform="Linux" version="9.0.0" num="1">silver</medal>
      <medal rating="5" platform="Mac" version="9.0.0" num="1">ungold</medal>
      <medal rating="3" platform="Mac" version="10.0.0" num="1">unbronze</medal>
      <category>Productivity/Word Processing</category>
      <bottletemplate>winxp</bottletemplate>
    </appprofile>
    <installprofile>
      <predependency>com.example.runtime</predependency>
      <installnotes>Insert the CD.</installnotes>
      <installnotes lang="de">Legen Sie die CD ein.</installnotes>
      <installerwinver>winxp</installerwinver>
      <defaulteassoc>.doc</defaulteassoc>
      <defaulteassoc>.docx</defaulteassoc>
    </installprofile>
  </app>
  <app appid="com.example.word" timestamp="2021-01-01T00:00:00-06:00">
    <cxversion product="cxoffice">11.0</cxversion>
    <cxversion product="cxoffice">12.0</cxversion>
    <name>Example Word</name>
    <name lang="en">Example Word</name>
    <appprofile>
      <description>An example word processor.</description>
      <medal rating="5" platform="Mac" version="12.0.0" num="2">gold</medal>
      <category>Productivity/Word Processing</category>
      <bottletemplate>win10</bottletemplate>
      <installerid>com.example.installer</installerid>
    </appprofile>
  </app>
  <app appid="com.example.metal" timestamp="2020-01-01T00:00:00-06:00">
    <cxversion product="cxoffice">10.0</cxversion>
    <name lang="en">Metal Only</name>
    <appprofile>
      <description lang="en">No untagged description.</description>
      <medal rating="2" platform="Linux" version="10.0.0" num="1">knownnottowork</medal>
      <category>Games/Action</category>
    </appprofile>
    <installprofile/>
  </app>
</c4p>
"""

private func makeTempFile(contents: String, label: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cork-crosstie-\(label)-\(UUID().uuidString).xml")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}

/// Parses `contents` via a temporary file, removing it afterwards.
private func parseFixture(_ contents: String, label: String = "fixture") throws -> CrossTieIndex {
    let url = try makeTempFile(contents: contents, label: label)
    defer { try? FileManager.default.removeItem(at: url) }
    return try CrossTieParser.parse(fileURL: url)
}

func crossTieTests() -> [TestCase] {
    [
        TestCase(name: "crossTieParsesAndMergesAppRecords", body: {
            let index = try parseFixture(crossTieFixture)
            try expectEqual(index.apps.count, 2, "one entry per unique appid")

            guard let word = index.app(id: "com.example.word") else {
                throw TestFailure(description: "missing com.example.word")
            }
            try expectEqual(word.name, "Example Word")
            try expectEqual(word.localizedNames["de"], "Beispiel Word" as String?)
            try expectEqual(word.localizedNames["en"], "Example Word" as String?)
            try expectEqual(word.summary, "An example word processor." as String?)
            try expectEqual(word.category, "Productivity/Word Processing" as String?)
            try expectEqual(word.version, "12.0" as String?, "newest <cxversion> wins")
            try expectEqual(word.bottleTemplate, "win10" as String?, "scalars come from the newest/richest record")
            try expectEqual(word.dependencies, ["com.example.runtime"])
            try expectEqual(word.installerVersion, "winxp" as String?, "falls back to the record that had one")
            try expect(word.hasInstaller, "has an installprofile + installerid")
            try expectEqual(word.defaultAssociations, [".doc", ".docx"])
            try expectEqual(word.installNotes, "Insert the CD." as String?)
            try expectEqual(word.platforms, ["Linux", "Mac"])
        }),

        TestCase(name: "crossTieChoosesHighestMedalPreferringMac", body: {
            let index = try parseFixture(crossTieFixture)
            let word = try expectApp(index, "com.example.word")
            try expectEqual(word.rating, 5, "highest rating wins")
            try expectEqual(word.medal, "gold" as String?, "verified gold beats ungold at the same rating")
            try expectEqual(word.medalPlatform, "Mac" as String?, "Mac preferred over Linux")
        }),

        TestCase(name: "crossTieFallsBackToEnglishAndEmptyInstaller", body: {
            let index = try parseFixture(crossTieFixture)
            let metal = try expectApp(index, "com.example.metal")
            try expectEqual(metal.name, "Metal Only", "no untagged <name>, use English")
            try expectEqual(metal.summary, "No untagged description." as String?)
            try expectEqual(metal.rating, 2)
            try expectEqual(metal.medal, "knownnottowork" as String?)
            try expectEqual(metal.medalPlatform, "Linux" as String?)
            try expect(!metal.hasInstaller, "self-closing <installprofile/> is not an installer")
            try expect(metal.dependencies.isEmpty)
            try expect(metal.defaultAssociations.isEmpty)
        }),

        TestCase(name: "crossTieCategoryListAndSearch", body: {
            let index = try parseFixture(crossTieFixture)
            try expectEqual(index.categories, ["Games/Action", "Productivity/Word Processing"])
            let hits = index.search(CatalogQuery(text: "word"))
            try expectEqual(hits.map(\.id), ["com.example.word"])
            let gold = index.search(CatalogQuery(text: "", minRating: 5))
            try expectEqual(gold.map(\.id), ["com.example.word"])
            let games = index.search(CatalogQuery(categories: ["Games/Action"]))
            try expectEqual(games.map(\.id), ["com.example.metal"])
        }),

        TestCase(name: "crossTieStreamsLargeCatalogAndDedupes", body: {
            // 3,000 records across 1,500 unique appids — exercises the streaming
            // path without the 23 MB on-disk catalog.
            var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<c4p>\n"
            let unique = 1500
            for i in 0..<unique {
                for version in ["9.0", "10.0"] {
                    xml += """
                      <app appid="com.example.app\(i)" timestamp="2020-01-01T00:00:00-06:00">
                        <cxversion product="cxoffice">\(version)</cxversion>
                        <name>App \(i)</name>
                        <appprofile>
                          <description>Description \(i).</description>
                          <medal rating="5" platform="Mac" version="\(version).0" num="0">gold</medal>
                          <category>Games/Action</category>
                        </appprofile>
                      </app>
                    """
                    xml += "\n"
                }
            }
            xml += "</c4p>\n"

            let index = try parseFixture(xml, label: "large")
            try expectEqual(index.apps.count, unique)
            try expectEqual(Set(index.apps.map(\.id)).count, unique)
            try expectEqual(index.app(id: "com.example.app7")?.name, "App 7" as String?)
            try expectEqual(index.app(id: "com.example.app7")?.version, "10.0" as String?)
        }),

        TestCase(name: "crossTieMalformedXMLThrows", body: {
            try expectThrows(CrossTieParserError.self, "unterminated XML should throw") {
                _ = try parseFixture("<?xml version=\"1.0\"?><c4p><app appid=\"x\">")
            }
        }),

        TestCase(name: "compatDatabaseReturnsEmptyForOpaqueFormat", body: {
            // The real format is an undocumented, obfuscated 7-bit binary. The
            // parser must never throw and must yield an empty map so callers fall
            // back to recipe medals.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cork-compatdb-\(UUID().uuidString).dat")
            defer { try? FileManager.default.removeItem(at: url) }
            try Data((0..<256).map { UInt8($0 % 128) }).write(to: url)

            let database = try CompatDatabase(fileURL: url)
            try expectEqual(database.count, 0)
            try expectEqual(database.entries(appID: "com.codeweavers.c4.1"), [])
            try expectEqual(database.rating(appID: "com.codeweavers.c4.1", platform: "Mac"), nil)

            // Missing files also yield an empty map rather than throwing.
            let missing = url.appendingPathExtension("does-not-exist")
            let empty = try CompatDatabase(fileURL: missing)
            try expectEqual(empty.count, 0)
        }),
    ]
}

private func expectApp(_ index: CrossTieIndex, _ id: String) throws -> RecipeApp {
    guard let app = index.app(id: id) else {
        throw TestFailure(description: "missing app \(id)")
    }
    return app
}
