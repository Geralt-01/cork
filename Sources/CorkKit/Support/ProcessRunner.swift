import Foundation

public struct ProcessResult: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { status == 0 }
}

public enum ProcessRunner {
    @discardableResult
    public static func run(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global().async(group: group) {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        group.wait()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    @discardableResult
    public static func run(executable: String, arguments: [String] = [], environment: [String: String]? = nil) throws -> ProcessResult {
        try run(executable: URL(fileURLWithPath: executable), arguments: arguments, environment: environment)
    }
}
