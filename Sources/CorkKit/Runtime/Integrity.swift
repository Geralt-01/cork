import CryptoKit
import Foundation

public enum Integrity {
    public static func sha256(ofFileAt url: URL, progress: ((Double) -> Void)? = nil) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let total = (attributes?[.size] as? NSNumber)?.uint64Value
        var read: UInt64 = 0
        var hasher = SHA256()

        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
            read += UInt64(chunk.count)
            if let total, total > 0 {
                progress?(Double(read) / Double(total))
            }
        }

        return hasher.finalize().hexString
    }

    public static func sha256(of data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    public static func verify(file: URL, expected: String) throws {
        let actual = try sha256(ofFileAt: file)
        guard actual.lowercased() == expected.lowercased() else {
            throw CorkError.checksumMismatch(expected: expected, actual: actual)
        }
    }
}

public extension Sequence where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
