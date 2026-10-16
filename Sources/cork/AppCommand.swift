import ArgumentParser
import CorkEngine
import CorkKit
import Foundation

/// Browse CrossTie-style recipe catalogs (a user-supplied `crossover.tie`).
///
/// Cork never ships CodeWeavers data: pass a catalog path (or let Cork discover
/// an existing CrossOver installation) with `--catalog`.
///
/// NOTE: the engine track owns this file and completes the implementation.
struct AppCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app",
        abstract: "Search and inspect applications in a recipe catalog.",
        discussion: "Reads a CrossTie-format catalog that you supply; Cork does not bundle CrossOver data.",
        subcommands: [Search.self, Show.self]
    )

    struct Search: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Search the application catalog.")

        @Argument(help: "Search text (empty lists all).")
        var text: String = ""

        @Option(name: .long, help: "Path to a CrossTie catalog. Defaults to a detected CrossOver install.")
        var catalog: String?

        @Option(name: .long, help: "Maximum results.")
        var limit: Int = 25

        @Option(name: .long, help: "Minimum medal rating (1-5).")
        var minRating: Int?

        @Option(name: .long, help: "Filter by category.")
        var category: String?

        func run() throws {
            let url = try resolveCatalogURL(explicit: catalog)
            let catalog = try CrossTieCatalog(fileURL: url)
            let results = catalog.search(
                CatalogQuery(
                    text: text,
                    categories: category.map { [$0] } ?? [],
                    minRating: minRating,
                    limit: limit
                )
            )
            print(Terminal.bold("\(catalog.appCount) apps in \(url.lastPathComponent)"))
            for app in results {
                let rating = app.rating.map { "[\($0)/5]" } ?? ""
                print("  \(app.id)  \(app.name) \(rating)")
            }
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show one application's recipe.")

        @Argument(help: "Application id, e.g. com.codeweavers.c4.1")
        var id: String

        @Option(name: .long, help: "Path to a CrossTie catalog. Defaults to a detected CrossOver install.")
        var catalog: String?

        func run() throws {
            let url = try resolveCatalogURL(explicit: catalog)
            let catalog = try CrossTieCatalog(fileURL: url)
            guard let app = catalog.app(id: id) else {
                throw ValidationError("No app with id '\(id)'.")
            }
            print(Terminal.bold(app.name))
            print("  id:          \(app.id)")
            if let category = app.category { print("  category:    \(category)") }
            if let medal = app.medal { print("  medal:       \(medal)") }
            if let template = app.bottleTemplate { print("  bottle:      \(template)") }
            print("  installer:   \(app.hasInstaller ? "yes" : "no")")
            if !app.dependencies.isEmpty {
                print("  requires:    \(app.dependencies.joined(separator: ", "))")
            }
            if let summary = app.summary { print("  \(summary)") }
        }
    }

    /// Resolve the catalog path from an explicit option or CrossOver discovery.
}

/// Resolve a catalog path from an explicit option or CrossOver discovery.
private func resolveCatalogURL(explicit: String?) throws -> URL {
    if let explicit {
        let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("No catalog at \(url.path)")
        }
        return url
    }
    if let detected = CrossOverData.defaultTieURL() {
        return detected
    }
    throw ValidationError("No catalog specified. Pass --catalog /path/to/crossover.tie")
}
