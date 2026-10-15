import Foundation

public enum WineProcess {
    @discardableResult
    public static func runStreaming(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        logFile: URL? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) throws -> Int32 {
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

        var logHandle: FileHandle?
        if let logFile {
            try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            logHandle = try FileHandle(forWritingTo: logFile)
        }

        let sink = OutputSink(logHandle: logHandle, onLine: onLine)
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            sink.append(handle.availableData)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            sink.append(handle.availableData)
        }

        try process.run()
        process.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        sink.finish()
        try? logHandle?.close()

        return process.terminationStatus
    }

    @discardableResult
    public static func killServer(
        installation: WineInstallation,
        bottle: Bottle,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> ProcessResult {
        let environment = WineEnvironment.launchEnvironment(bottle: bottle, installation: installation, base: base)
        return try ProcessRunner.run(
            executable: installation.wineserverBinary,
            arguments: ["-k"],
            environment: environment
        )
    }

    @discardableResult
    public static func runAndWait(
        installation: WineInstallation,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil
    ) throws -> ProcessResult {
        try ProcessRunner.run(
            executable: installation.wineBinary,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory
        )
    }
}

private final class OutputSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.cork.wine.output")
    private let logHandle: FileHandle?
    private let onLine: (@Sendable (String) -> Void)?
    private var buffer = Data()

    init(logHandle: FileHandle?, onLine: (@Sendable (String) -> Void)?) {
        self.logHandle = logHandle
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async {
            self.logHandle?.write(data)
            self.buffer.append(data)
            while let index = self.buffer.firstIndex(of: 0x0A) {
                let line = self.buffer[self.buffer.startIndex..<index]
                self.buffer.removeSubrange(self.buffer.startIndex...index)
                self.onLine?(String(decoding: line, as: UTF8.self))
            }
        }
    }

    func finish() {
        queue.sync {
            if !buffer.isEmpty {
                onLine?(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll()
            }
        }
    }
}
