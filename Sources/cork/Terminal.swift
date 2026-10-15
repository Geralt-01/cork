import Foundation

enum Terminal {
    static let useColor = isatty(STDOUT_FILENO) == 1

    static func bold(_ text: String) -> String { wrap(text, "1") }
    static func green(_ text: String) -> String { wrap(text, "32") }
    static func red(_ text: String) -> String { wrap(text, "31") }
    static func yellow(_ text: String) -> String { wrap(text, "33") }
    static func cyan(_ text: String) -> String { wrap(text, "36") }
    static func dim(_ text: String) -> String { wrap(text, "2") }

    private static func wrap(_ text: String, _ code: String) -> String {
        useColor ? "\u{001B}[\(code)m\(text)\u{001B}[0m" : text
    }

    static func check(_ text: String) -> String { green("✓") + " " + text }
    static func cross(_ text: String) -> String { red("✗") + " " + text }
    static func warn(_ text: String) -> String { yellow("!") + " " + text }
    static func arrow(_ text: String) -> String { cyan("→") + " " + text }
    static func bullet(_ text: String) -> String { dim("•") + " " + text }

    static func error(_ message: String) {
        FileHandle.standardError.write(Data((red("error:") + " " + message + "\n").utf8))
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(bytes)
        var index = 0
        while value >= 1024 && index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: index == 0 ? "%.0f %@" : "%.1f %@", value, units[index])
    }

    static func formatBytes(_ bytes: Int) -> String {
        formatBytes(Int64(bytes))
    }
}

final class ProgressLine {
    private let lock = NSLock()
    private var finished = false

    func update(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        FileHandle.standardError.write(Data("\r\u{001B}[2K  \(text)".utf8))
    }

    func finish(_ text: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        if let text {
            FileHandle.standardError.write(Data("\r\u{001B}[2K  \(text)\n".utf8))
        } else {
            FileHandle.standardError.write(Data("\r\u{001B}[2K".utf8))
        }
        finished = true
    }
}
