import ArgumentParser
import CorkEngine
import CorkKit
import Foundation

/// Install an application from a recipe catalog into a bottle.
///
/// NOTE: the install track owns this file and completes the implementation.
struct InstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install a Windows application from a recipe catalog into a bottle.",
        discussion: "Reads a CrossTie-format catalog that you supply; Cork does not bundle CrossOver data."
    )

    @Argument(help: "Name of the target bottle.")
    var bottle: String

    @Argument(help: "Application id, e.g. com.codeweavers.c4.1")
    var appID: String

    @Option(name: .long, help: "Path to a CrossTie catalog. Defaults to a detected CrossOver install.")
    var catalog: String?

    func run() async throws {
        let url = try locateCatalog(explicit: catalog)
        let recipes = try CrossTieInstallRecipes(fileURL: url)
        guard let recipe = recipes.installRecipe(appID: appID) else {
            throw ValidationError("No install recipe for '\(appID)' in \(url.lastPathComponent).")
        }
        let installer = WineInstaller()
        try await installer.install(recipe: recipe, into: bottle) { event in
            switch event {
            case .resolving(let what): print(Terminal.arrow("resolving \(what)"))
            case .downloading(let name, _): print(Terminal.arrow("downloading \(name)"))
            case .running(let what): print(Terminal.arrow("running \(what)"))
            case .copying(let what): print(Terminal.arrow("copying \(what)"))
            case .shortcut(let what): print(Terminal.arrow("shortcut \(what)"))
            case .registry(let what): print(Terminal.arrow("registry \(what)"))
            case .warning(let message): print(Terminal.warn(message))
            case .finished: print(Terminal.check("installed \(appID)"))
            }
        }
    }
}
