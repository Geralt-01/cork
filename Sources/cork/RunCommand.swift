import ArgumentParser
import CorkKit
import Foundation

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a Windows executable inside a bottle.",
        discussion: "Everything after '--' is passed to the Windows program."
    )

    @Argument(help: "Name of the bottle.")
    var bottle: String

    @Argument(help: "Path to a Windows .exe or .msi.")
    var executable: String

    @Flag(name: .long, help: "Launch and return immediately instead of waiting for the program to exit.")
    var detach = false

    @Argument(parsing: .captureForPassthrough, help: "Arguments for the Windows program.")
    var passthrough: [String] = []

    func run() async throws {
        let manager = try BottleManager()
        let url = URL(fileURLWithPath: (executable as NSString).expandingTildeInPath)

        print(Terminal.arrow("launching \(url.lastPathComponent) in bottle '\(bottle)'"))
        let status = try manager.run(
            named: bottle,
            executable: url,
            arguments: passthrough,
            detach: detach,
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
