import Foundation

public struct WineInstallation: Sendable {
    public let root: URL
    public let wineBinary: URL
    public let wineserverBinary: URL
    public let winebootBinary: URL

    public var binDirectory: URL {
        root.appendingPathComponent("bin", isDirectory: true)
    }

    public var libDirectory: URL {
        root.appendingPathComponent("lib/wine", isDirectory: true)
    }

    public static func detect(in root: URL) throws -> WineInstallation {
        let fm = FileManager.default
        let bin = root.appendingPathComponent("bin", isDirectory: true)

        func firstExecutable(_ names: [String]) -> URL? {
            for name in names {
                let candidate = bin.appendingPathComponent(name)
                if fm.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
            return nil
        }

        guard let wine = firstExecutable(["wine64", "wine"]) else {
            throw CorkError.wineBinaryMissing(path: bin.appendingPathComponent("wine64").path)
        }
        guard let wineserver = firstExecutable(["wineserver"]) else {
            throw CorkError.wineBinaryMissing(path: bin.appendingPathComponent("wineserver").path)
        }
        let wineboot = firstExecutable(["wineboot"]) ?? bin.appendingPathComponent("wineboot")

        return WineInstallation(
            root: root,
            wineBinary: wine,
            wineserverBinary: wineserver,
            winebootBinary: wineboot
        )
    }

    public func version() -> String? {
        var environment = ProcessInfo.processInfo.environment
        environment["WINEDEBUG"] = "-all"
        guard let result = try? ProcessRunner.run(
            executable: wineBinary,
            arguments: ["--version"],
            environment: environment
        ) else { return nil }
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }

    public func isRosettaAvailable() -> Bool {
        let result = try? ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/arch"),
            arguments: ["-x86_64", "/usr/bin/true"]
        )
        return result?.succeeded ?? false
    }

    public func baseEnvironment(patching current: [String: String]) -> [String: String] {
        var environment = current
        let path = binDirectory.path
        if let existing = environment["PATH"], !existing.isEmpty {
            environment["PATH"] = "\(path):\(existing)"
        } else {
            environment["PATH"] = path
        }
        environment["WINELOADER"] = wineBinary.path
        environment["WINESERVER"] = wineserverBinary.path
        environment["WINEDLLPATH"] = libDirectory.path
        environment.removeValue(forKey: "DYLD_LIBRARY_PATH")
        environment.removeValue(forKey: "DYLD_FALLBACK_LIBRARY_PATH")
        return environment
    }
}
