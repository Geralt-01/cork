import ArgumentParser
import CorkKit
import Foundation

@main
struct Cork: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cork",
        abstract: "Run Windows games and applications on macOS.",
        discussion: "Cork is an open-source, Wine-based compatibility layer with a managed runtime and per-bottle graphics backends.",
        version: CorkVersion.current,
        subcommands: [
            RuntimeCommand.self,
            BottleCommand.self,
            RunCommand.self,
            ExecCommand.self,
            DoctorCommand.self,
        ]
    )

    static func main() async {
        do {
            var command = try await Self.asyncParseAsRoot(nil)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch {
            if error is CorkError {
                printErrorAndExit(error)
            }
            Self.exit(withError: error)
        }
    }
}

func printErrorAndExit(_ error: Error) -> Never {
    if let corkError = error as? CorkError {
        Terminal.error(corkError.errorDescription ?? "\(corkError)")
        if let suggestion = corkError.recoverySuggestion {
            FileHandle.standardError.write(Data((Terminal.dim("hint: " + suggestion) + "\n").utf8))
        }
    } else {
        Terminal.error("\(error)")
    }
    Foundation.exit(1)
}
