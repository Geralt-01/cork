import ArgumentParser
import CorkKit
import Foundation

struct ExecCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Run a Wine command inside a bottle (cmd, notepad, winecfg, reg, …).",
        discussion: "Use 'cork run' for an .exe file; use 'cork exec' for Wine's built-in commands."
    )

    @Argument(help: "Name of the bottle.")
    var bottle: String

    @Argument(help: "The command to run, e.g. cmd, notepad, winecfg.")
    var command: String

    @Argument(parsing: .captureForPassthrough, help: "Arguments for the command.")
    var arguments: [String] = []

    func run() async throws {
        let manager = try BottleManager()
        let status = try manager.exec(
            named: bottle,
            command: command,
            arguments: arguments,
            onLine: { line in
                if !line.isEmpty {
                    print(line)
                }
            }
        )
        if status != 0 {
            throw ExitCode(status)
        }
    }
}
