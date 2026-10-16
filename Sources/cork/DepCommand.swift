import ArgumentParser
import CorkEngine
import CorkKit
import Foundation

/// Browse and install winetricks-style dependency components.
///
/// NOTE: the dependencies track owns this file and completes the implementation.
struct DepCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "deps",
        abstract: "Install dependency components (vcrun, dotnet, DirectX, …) into a bottle.",
        subcommands: [List.self, Install.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List available dependency components.")

        @Option(name: .long, help: "Filter by category.")
        var category: String?

        func run() {
            let manager = DependencyManager()
            let all = manager.components()
            print(Terminal.bold("\(all.count) dependency components"))
            for component in all where category.map({ component.category.caseInsensitiveCompare($0) == .orderedSame }) ?? true {
                let id = component.id.padding(toLength: 14, withPad: " ", startingAt: 0)
                print("  \(id)\(component.name)  \(component.summary ?? "")")
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install a dependency component into a bottle.")

        @Argument(help: "Name of the target bottle.")
        var bottle: String

        @Argument(help: "Component id, e.g. vcrun2015")
        var component: String

        func run() async throws {
            let manager = DependencyManager()
            guard manager.component(id: component) != nil else {
                throw ValidationError("Unknown component '\(component)'. Run 'cork deps list'.")
            }
            try await manager.install(componentID: component, into: bottle) { event in
                switch event {
                case .resolving(let what): print(Terminal.arrow("resolving \(what)"))
                case .downloading(let name, _): print(Terminal.arrow("downloading \(name)"))
                case .running(let what): print(Terminal.arrow("running \(what)"))
                case .copying(let what): print(Terminal.arrow("copying \(what)"))
                case .shortcut(let what): print(Terminal.arrow("shortcut \(what)"))
                case .registry(let what): print(Terminal.arrow("registry \(what)"))
                case .warning(let message): print(Terminal.warn(message))
                case .finished: print(Terminal.check("installed \(component)"))
                }
            }
        }
    }
}
