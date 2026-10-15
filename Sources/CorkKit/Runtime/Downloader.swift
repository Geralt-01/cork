import Foundation

public struct DownloadProgress: Sendable {
    public let receivedBytes: Int64
    public let totalBytes: Int64

    public var fraction: Double? {
        totalBytes > 0 ? min(1, Double(receivedBytes) / Double(totalBytes)) : nil
    }

    public var megabytesReceived: Double {
        Double(receivedBytes) / 1_048_576
    }
}

public enum Downloader {
    public static func download(
        from url: URL,
        to destination: URL,
        progress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        let session = DownloadSession(destination: destination, progress: progress)
        try await session.start(url: url)
    }
}

private final class DownloadSession: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: (@Sendable (DownloadProgress) -> Void)?
    private var continuation: CheckedContinuation<Void, Error>?
    private var session: URLSession?
    private var didFinishDownloading = false
    private var completed = false
    private var sourceURLString = ""

    init(destination: URL, progress: (@Sendable (DownloadProgress) -> Void)?) {
        self.destination = destination
        self.progress = progress
    }

    func start(url: URL) async throws {
        sourceURLString = url.absoluteString
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60
            configuration.timeoutIntervalForResource = 60 * 60 * 2
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        progress?(DownloadProgress(receivedBytes: totalBytesWritten, totalBytes: totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(CorkError.downloadFailed(url: sourceURLString, underlying: "HTTP \(http.statusCode)")))
            return
        }
        do {
            let fm = FileManager.default
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: location, to: destination)
            didFinishDownloading = true
        } catch {
            finish(.failure(CorkError.downloadFailed(url: sourceURLString, underlying: error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(CorkError.downloadFailed(url: sourceURLString, underlying: error.localizedDescription)))
        } else if didFinishDownloading {
            finish(.success(()))
        } else {
            finish(.failure(CorkError.downloadFailed(url: sourceURLString, underlying: "download did not produce a file")))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !completed else { return }
        completed = true
        session?.invalidateAndCancel()
        session = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
