import Foundation

extension String {
    func padded(_ width: Int) -> String {
        let length = count
        guard length < width else { return self }
        return self + String(repeating: " ", count: width - length)
    }

    func truncated(_ width: Int) -> String {
        guard count > width, width > 1 else { return self }
        return String(prefix(width - 1)) + "…"
    }
}
