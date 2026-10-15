import Foundation
import CorkKit

func integrityTests() -> [TestCase] {
    [
        TestCase(name: "knownDigests", body: {
            try expectEqual(
                Integrity.sha256(of: Data()),
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
            )
            try expectEqual(
                Integrity.sha256(of: Data("abc".utf8)),
                "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
            )
        }),
        TestCase(name: "fileDigestMatchesDataDigest", body: {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cork-\(UUID().uuidString).bin")
            let data = Data((0..<200_000).map { UInt8($0 % 251) })
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            try expectEqual(try Integrity.sha256(ofFileAt: url), Integrity.sha256(of: data))
        }),
        TestCase(name: "verifyThrowsOnMismatch", body: {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cork-\(UUID().uuidString).bin")
            try Data("hello".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            try expectThrows(CorkError.self) {
                try Integrity.verify(file: url, expected: String(repeating: "0", count: 64))
            }
        }),
        TestCase(name: "verifyAcceptsCorrectDigest", body: {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cork-\(UUID().uuidString).bin")
            try Data("hello".utf8).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            try Integrity.verify(file: url, expected: Integrity.sha256(of: Data("hello".utf8)))
        }),
    ]
}
