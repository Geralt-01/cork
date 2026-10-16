import CorkKit
import Foundation

func integrationTests() -> [TestCase] {
    [
        TestCase(name: "installedRuntimeVerifies", body: {
            let manager = try RuntimeManager()
            let installedIDs = Set(manager.installedComponents().map(\.id))
            guard !installedIDs.isEmpty else {
                print("      (no runtime installed at \(manager.paths.runtimesDirectory.path), skipped)")
                return
            }
            for result in manager.verify() where installedIDs.contains(result.id) {
                try expect(result.installed, "\(result.id): \(result.detail)")
                try expect(result.detail.hasPrefix("ok"), "\(result.id): \(result.detail)")
            }
        }),
    ]
}

var suites: [(String, [TestCase])] = [
    ("Manifest", manifestTests()),
    ("Integrity", integrityTests()),
    ("Archive", archiveTests()),
    ("BottleSettings", bottleSettingsTests()),
    ("Bottle", bottleTests()),
    ("CrossTie", crossTieTests()),
    ("InstallRecipe", installRecipeTests()),
    ("Installer", installerTests()),
    ("Bundler", bundlerTests()),
]

if ProcessInfo.processInfo.environment["CORK_INTEGRATION"] == "1" {
    suites.append(("Integration", integrationTests()))
}

var passed = 0
var failures: [String] = []

print("Cork test suite")
print(String(repeating: "─", count: 48))

for (suite, tests) in suites {
    print("\(suite)")
    for test in tests {
        do {
            try test.body()
            passed += 1
            print("  ✓ \(test.name)")
        } catch let failure as TestFailure {
            failures.append("\(suite).\(test.name): \(failure)")
            print("  ✗ \(test.name)")
            print("      \(failure)")
        } catch {
            failures.append("\(suite).\(test.name): \(type(of: error)) \(error)")
            print("  ✗ \(test.name)")
            print("      unexpected \(type(of: error)): \(error)")
        }
    }
}

print(String(repeating: "─", count: 48))
print("\(passed) passed, \(failures.count) failed")

if !failures.isEmpty {
    print("")
    print("Failures:")
    for failure in failures {
        print("  • \(failure)")
    }
    exit(1)
}
