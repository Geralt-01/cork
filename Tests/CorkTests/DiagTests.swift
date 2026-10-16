import CorkEngine
import CorkKit
import Foundation

/// Tests for diagnostics + cxfixes. Owned by the diagnostics track.
func diagTests() -> [TestCase] {
    [
        TestCase(name: "hostArchitectureReturnsValue", body: {
            let architecture = Diagnostics.hostArchitecture()
            try expect(!architecture.isEmpty, "architecture should not be empty")
            try expect(architecture != "unknown", "architecture should be readable on macOS, got \(architecture)")
        }),
        TestCase(name: "reportHasFailures", body: {
            let withFailure = DiagnosticReport(checks: [
                DiagnosticCheck(id: "a", title: "A", status: .pass),
                DiagnosticCheck(id: "b", title: "B", status: .fail),
            ])
            try expect(withFailure.hasFailures, "a fail check should set hasFailures")

            let withoutFailure = DiagnosticReport(checks: [
                DiagnosticCheck(id: "a", title: "A", status: .pass),
                DiagnosticCheck(id: "b", title: "B", status: .warn),
                DiagnosticCheck(id: "c", title: "C", status: .skipped),
            ])
            try expect(!withoutFailure.hasFailures, "warn/skipped should not count as failures")
            try expectEqual(withoutFailure.warnings.count, 1)
            try expectEqual(withoutFailure.failures.count, 0)
        }),
        TestCase(name: "missingBottleIsFailNotThrow", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-diag-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let paths = CorkPaths(root: root)

            // Must not throw even though there are no bottles and no runtime.
            let report = try Diagnostics(paths: paths).run(bottle: "does-not-exist")
            try expectEqual(report.bottle, "does-not-exist")

            guard let check = report.check(id: "bottle.exists") else {
                throw TestFailure(description: "missing bottle.exists check")
            }
            try expectEqual(check.status, .fail)
            try expect(report.hasFailures)

            // The dependent checks are skipped, not fabricated as passing.
            try expectEqual(report.check(id: "bottle.prefix")?.status, .skipped)
            try expectEqual(report.check(id: "bottle.graphics")?.status, .skipped)
        }),
        TestCase(name: "runWithoutBottleIncludesHostAndRuntime", body: {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("cork-diag-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let report = try Diagnostics(paths: CorkPaths(root: root)).run()

            try expect(report.check(id: "host.cpu") != nil, "host.cpu check expected")
            try expect(report.check(id: "host.macos") != nil, "host.macos check expected")
            try expect(report.check(id: "host.disk") != nil, "host.disk check expected")
            try expect(report.check(id: "runtime.wine") != nil, "runtime.wine check expected")
            try expect(report.bottle == nil)
            // No per-bottle checks when no bottle is named.
            try expect(report.check(id: "bottle.exists") == nil)
        }),
        TestCase(name: "statusMapping", body: {
            // Status -> exit-code mapping and CLI glyphs.
            try expect(DiagnosticStatus.fail.isFailure)
            try expect(!DiagnosticStatus.pass.isFailure)
            try expect(!DiagnosticStatus.warn.isFailure)
            try expect(!DiagnosticStatus.skipped.isFailure)

            try expectEqual(DiagnosticStatus.pass.symbol, "✓")
            try expectEqual(DiagnosticStatus.warn.symbol, "!")
            try expectEqual(DiagnosticStatus.fail.symbol, "✗")
            try expectEqual(DiagnosticStatus.skipped.symbol, "–")

            // Raw values are part of the Codable/CLI contract.
            try expectEqual(DiagnosticStatus.pass.rawValue, "pass")
            try expectEqual(DiagnosticStatus.warn.rawValue, "warn")
            try expectEqual(DiagnosticStatus.fail.rawValue, "fail")
            try expectEqual(DiagnosticStatus.skipped.rawValue, "skipped")
        }),
        TestCase(name: "cxfixesParsesInlineFixture", body: {
            let url = writeFixture("""
            <cxfixes release="test">
              <distributions>
                <distribution id="dummy" name="Dummy"/>
              </distributions>
              <fixes>
                <fix id="pygi" title="Missing Python 3 GObject introspection support"
                     description="GObject support is needed to run the installer.">
                  <cx id="cx19" level="required"/>
                  <fixfor distribution="arch"><package name="python-gobject"/></fixfor>
                </fix>
                <fix id="gir-data" title="Missing Python 3 GTK 3 support">
                  <description>GTK 3 support is needed.</description>
                </fix>
                <fix id="bare" title="Bare fix"><cx id="cx12"/></fix>
              </fixes>
            </cxfixes>
            """)
            defer { try? FileManager.default.removeItem(at: url) }

            let parsed = try CxFixesParser.parse(fileURL: url)
            try expectEqual(parsed.count, 3)
            try expectEqual(
                parsed["pygi"] ?? [],
                ["GObject support is needed to run the installer."]
            )
            // Falls back to a child <description> when there is no attribute.
            try expectEqual(parsed["gir-data"] ?? [], ["GTK 3 support is needed."])
            // Falls back to the title when there is no description at all.
            try expectEqual(parsed["bare"] ?? [], ["Bare fix"])

            let fixes = try CxFixes(fileURL: url)
            try expectEqual(fixes.fixCount, 3)
            try expectEqual(fixes.fixes(appID: "pygi").count, 1)
            try expect(fixes.fixes(appID: "absent").isEmpty)
            try expectEqual(fixes.fixIDs, ["bare", "gir-data", "pygi"])
        }),
        TestCase(name: "cxfixesNeverThrowsOnBadInput", body: {
            // Malformed XML.
            let malformed = writeFixture("<cxfixes><fixes><fix id=\"x\"></cxfixes>")
            defer { try? FileManager.default.removeItem(at: malformed) }
            try expect((try CxFixesParser.parse(fileURL: malformed)).isEmpty)

            // Valid XML, but not a cxfixes document.
            let unrelated = writeFixture("<?xml version=\"1.0\"?><nothere><fix id=\"x\" title=\"x\"/></nothere>")
            defer { try? FileManager.default.removeItem(at: unrelated) }
            try expect((try CxFixesParser.parse(fileURL: unrelated)).isEmpty)

            // Missing file.
            let missing = FileManager.default.temporaryDirectory.appendingPathComponent("cork-missing-\(UUID().uuidString).xml")
            try expect((try CxFixesParser.parse(fileURL: missing)).isEmpty)
        }),
        TestCase(name: "cxfixesDiscoveryHonoursOverride", body: {
            let url = writeFixture("<cxfixes><fixes><fix id=\"a\" description=\"A\"/></fixes></cxfixes>")
            defer { try? FileManager.default.removeItem(at: url) }

            let found = CxFixesDiscovery.candidateURL(environment: ["CORK_CXFIXES": url.path])
            try expectEqual(found?.path, url.path)

            let loaded = CxFixesDiscovery.load(environment: ["CORK_CXFIXES": url.path])
            try expectEqual(loaded?.fixCount, 1)

            // A stale override that does not exist yields nothing.
            try expect(CxFixesDiscovery.candidateURL(environment: ["CORK_CXFIXES": "/nonexistent/cxfixes.xml"]) == nil)
        }),
    ]
}

private func writeFixture(_ contents: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("cork-cxfixes-\(UUID().uuidString).xml")
    try? contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}
