import Foundation
import CorkKit

/// One entry in the bottle `drive_c` browser. Value type so it can be produced
/// on a background task and handed to the main actor.
struct BrowserEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let isDirectory: Bool
    let size: Int64

    var id: String { url.path }
    var name: String { url.lastPathComponent }

    /// True for Windows executables — the only files that can be launched or
    /// bundled.
    var isExecutable: Bool {
        !isDirectory && url.pathExtension.lowercased() == "exe"
    }
}

/// A Windows program associated with a bottle, either pinned in the bottle
/// metadata or discovered by scanning `drive_c`.
struct DiscoveredProgram: Identifiable, Hashable, Sendable {
    enum Origin: String, Sendable {
        case pinned
        case discovered

        var label: String {
            switch self {
            case .pinned: return "Pinned"
            case .discovered: return "Found in drive_c"
            }
        }
    }

    let name: String
    let url: URL
    let arguments: [String]
    let origin: Origin

    var id: String { url.path }
}

/// Pure helpers backing the bottle file browser and program discovery.
enum BottleFiles {

    /// `~/Applications`, created on demand by the bundler.
    static var defaultApplicationsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
    }

    /// Recursively finds `.exe` files beneath `root`, skipping Wine's own system
    /// directories and the Cork scratch area. Bounded by `limit` and a maximum
    /// depth so a huge prefix cannot stall the UI.
    static func discoverExecutables(under root: URL, limit: Int = 400) -> [DiscoveredProgram] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return [] }

        // Directory names that never contain user-facing programs.
        let skipped: Set<String> = [
            "windows", "ProgramData", "users", "cork",
            "system32", "syswow64", "winsxs", "Microsoft.NET",
        ]

        var results: [DiscoveredProgram] = []
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        let maxDepth = 6

        while let (directory, depth) = queue.popLast() {
            if results.count >= limit { break }
            guard let contents = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                if results.count >= limit { break }
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDirectory {
                    guard depth < maxDepth,
                          !skipped.contains(url.lastPathComponent) else { continue }
                    queue.append((url, depth + 1))
                } else if url.pathExtension.lowercased() == "exe" {
                    results.append(
                        DiscoveredProgram(
                            name: url.deletingPathExtension().lastPathComponent,
                            url: url,
                            arguments: [],
                            origin: .discovered
                        )
                    )
                }
            }
        }

        return results.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Merges metadata pins with a discovered list, de-duplicating by path and
    /// preferring the pinned entry (which may carry default arguments).
    static func merge(pins: [PinnedProgram], discovered: [DiscoveredProgram]) -> [DiscoveredProgram] {
        var byPath: [String: DiscoveredProgram] = [:]
        var order: [String] = []

        func key(for path: String) -> String {
            let expanded = (path as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }

        for pin in pins {
            let url = URL(fileURLWithPath: (pin.path as NSString).expandingTildeInPath)
            let k = url.standardizedFileURL.path
            if byPath[k] == nil { order.append(k) }
            byPath[k] = DiscoveredProgram(
                name: pin.name.isEmpty ? url.lastPathComponent : pin.name,
                url: url,
                arguments: pin.arguments,
                origin: .pinned
            )
        }

        for program in discovered {
            let k = key(for: program.url.path)
            if byPath[k] == nil {
                order.append(k)
                byPath[k] = program
            }
        }

        return order.compactMap { byPath[$0] }
    }
}
