import ArgumentParser
import Foundation

enum Confirm {
    /// Asks the user to confirm a destructive operation.
    ///
    /// Prompts on stderr when stdin is a terminal. In non-interactive sessions the
    /// caller must pass `--yes`, otherwise this throws.
    static func ask(_ summary: String, yes: Bool) throws {
        guard !yes else { return }
        guard isatty(STDIN_FILENO) == 1 else {
            throw ValidationError("Confirmation is required but stdin is not a terminal. Pass --yes to proceed.")
        }
        FileHandle.standardError.write(Data("\(summary) [y/N] ".utf8))
        let answer = (readLine() ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard answer == "y" || answer == "yes" else {
            print(Terminal.dim("Aborted."))
            Foundation.exit(0)
        }
    }
}
