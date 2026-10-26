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
            try logHandle?.truncate(atOffset: 0)
        }

        let sink = OutputSink(logHandle: logHandle, onLine: onLine)
        let eof = DispatchGroup()
        eof.enter()
        eof.enter()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                eof.leave()
            } else {
                sink.append(data)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                eof.leave()
            } else {
                sink.append(data)
            }
        }

        try process.run()
        process.waitUntilExit()

        // Wait for the pipe readers to deliver everything written before exit.
        // A detached child can keep the pipes open indefinitely (for example
        // `wine start /unix`), so bound the wait instead of blocking `--detach`.
        if eof.wait(timeout: .now() + .milliseconds(500)) == .timedOut {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
        }
        sink.finish()
        try? logHandle?.close()

        return process.terminationStatus
    }

    /// Start a process and return as soon as it has been spawned. Output goes to
    /// `logFile`; the child is never awaited, so `--detach` cannot block on a
    /// launcher (such as `wine start` or `msiexec`) that stays alive.
    public static func launchDetached(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        logFile: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        var logHandle: FileHandle?
        if let logFile {
            try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: logFile.path, contents: nil)
            let handle = try FileHandle(forWritingTo: logFile)
            try handle.truncate(atOffset: 0)
            logHandle = handle
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        try process.run()
        // The child has its own duplicated descriptors after spawn; the parent
        // can close its handles and exit without affecting it.
        try? logHandle?.close()
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
    private var finished = false

    init(logHandle: FileHandle?, onLine: (@Sendable (String) -> Void)?) {
        self.logHandle = logHandle
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async {
            guard !self.finished else { return }
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
            self.finished = true
            if !buffer.isEmpty {
                onLine?(String(decoding: buffer, as: UTF8.self))
                buffer.removeAll()
            }
        }
    }
}
