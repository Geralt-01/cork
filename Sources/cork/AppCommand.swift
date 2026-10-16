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
        subcommands: [Search.self, Show.self, Recipe.self, Rating.self]
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
            if let rating = app.rating { print("  rating:      \(rating)/5") }
            if let medal = app.medal { print("  medal:       \(medal)") }
            if let version = app.version { print("  version:     \(version)") }
            if let template = app.bottleTemplate { print("  bottle:      \(template)") }
            print("  installer:   \(app.hasInstaller ? "yes" : "no")")
            if let installerVersion = app.installerVersion {
                print("  win version: \(installerVersion)")
            }
            if !app.dependencies.isEmpty {
                print("  requires:    \(app.dependencies.joined(separator: ", "))")
            }
            if !app.defaultAssociations.isEmpty {
                print("  opens:       \(app.defaultAssociations.joined(separator: ", "))")
            }
            if let notes = app.installNotes { print("  notes:       \(notes)") }
            if let summary = app.summary { print("  \(summary)") }
        }
    }

    /// Print the resolved compatibility rating for one app id.
    ///
    /// Prefers the CrossOver compatibility database when it can be read and
    /// falls back to the recipe medal from the catalog.
    struct Rating: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show an application's compatibility medal/rating.",
            discussion: "Prefers the CrossOver compatibility database, then falls back to the recipe medal from a catalog you supply."
        )

        @Argument(help: "Application id, e.g. com.codeweavers.c4.1")
        var appID: String

        @Option(name: .long, help: "Path to a CrossTie catalog. Defaults to a detected CrossOver install.")
        var catalog: String?

        func run() throws {
            let url = try locateCatalog(explicit: catalog)
            let catalog = try CrossTieCatalog(fileURL: url)

            // The compatibility database is best-effort: the shipped file is an
            // obfuscated binary that Cork cannot decode, in which case ratings
            // come from the recipe medal instead.
            var compat: CompatDatabase?
            if let compatURL = CrossOverData.defaultCompatDatabaseURL() {
                compat = try? CompatDatabase(fileURL: compatURL)
            }

            guard let resolved = CompatRating.resolveDetailed(appID: appID, catalog: catalog, compat: compat) else {
                throw ValidationError("No rating for '\(appID)' in \(url.lastPathComponent).")
            }

            let entry = resolved.entry
            print(Terminal.bold(entry.appID))
            print("  medal:    \(entry.medal.isEmpty ? "—" : entry.medal)")
            print("  rating:   \(entry.rating > 0 ? "\(entry.rating)/5" : "unknown")")
            print("  platform: \(entry.platform.isEmpty ? "—" : entry.platform)")
            print("  source:   \(resolved.source.rawValue)")
        }
    }

    /// Resolve the catalog path from an explicit option or CrossOver discovery.
}

/// Print the ordered install recipe (steps + reboot flag) for one app id.
struct Recipe: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show one application's install recipe (ordered steps).",
        discussion: "Extracts installer steps from a CrossTie catalog that you supply; Cork does not bundle CrossOver data."
    )

    @Argument(help: "Application id, e.g. com.codeweavers.c4.4225")
    var appID: String

    @Option(name: .long, help: "Path to a CrossTie catalog. Defaults to a detected CrossOver install.")
    var catalog: String?

    func run() throws {
        let url = try locateCatalog(explicit: catalog)
        let recipes = try CrossTieInstallRecipes(fileURL: url)
        guard let recipe = recipes.installRecipe(appID: appID) else {
            throw ValidationError("No install recipe for '\(appID)' in \(url.lastPathComponent).")
        }

        print(Terminal.bold("Recipe for \(recipe.appID)"))
        if recipe.steps.isEmpty {
            print("  (no steps)")
        }
        for (index, step) in recipe.steps.enumerated() {
            var line = "  \(index + 1). \(describe(step))"
            if let note = step.description, !note.isEmpty {
                line += Terminal.dim(" — \(note)")
            }
            print(line)
        }
        print(Terminal.bold("  requiresReboot: \(recipe.requiresReboot)"))
        if !recipe.dllOverrides.isEmpty {
            print("  dllOverrides:   \(recipe.dllOverrides.joined(separator: ", "))")
        }
    }

    private func describe(_ step: InstallStep) -> String {
        switch step.kind {
        case .download:
            return "download \(step.url ?? "?") → \(step.fileName ?? "?")"
        case .setWindowsVersion:
            return "setWindowsVersion \(step.windowsVersion ?? "?")"
        case .copyFiles:
            return "copyFiles \(step.source ?? "?") → \(step.destination ?? "?")"
        case .registry:
            return "registry \(step.registryKey ?? "?") \\ \(step.registryName ?? "?") = \(step.registryData ?? "")"
        case .createShortcut:
            return "createShortcut \(step.destination ?? "?") → \(step.source ?? "?")"
        case .runInstaller, .runCommand:
            var parts = [step.command ?? "?"]
            if !step.arguments.isEmpty { parts.append(contentsOf: step.arguments) }
            var line = "\(step.kind.rawValue) \(parts.joined(separator: " "))"
            if !step.silentArguments.isEmpty {
                line += " (silent: \(step.silentArguments.joined(separator: " ")))"
            }
            return line
        }
    }
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
