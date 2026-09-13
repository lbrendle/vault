import Foundation
import CryptoKit

public struct StarterModel: Decodable, Sendable {
    public struct File: Decodable, Sendable {
        public let name: String
        public let bytes: Int64
        public let sha256: String
    }
    public let id: String
    public let name: String
    public let repository: String
    public let revision: String
    public let license: String
    public let precision: String
    public let files: [File]
    public var folder: String { String(repository.split(separator: "/").last!) }
    public var bytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var json: [String: Any] {
        ["id": id, "name": name, "folder": folder, "bytes": bytes,
         "precision": precision, "license": license,
         "repository": repository, "installed": (try? ModelLibrary.selected(folder)) != nil]
    }
    public static func catalog(at url: URL) throws -> [StarterModel] {
        struct Catalog: Decodable { let models: [StarterModel] }
        let models = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).models
        for model in models {
            guard model.repository.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil,
                  model.revision.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
                  !model.files.isEmpty else { throw VaultError.message("Invalid starter catalog") }
            for file in model.files {
                guard !file.name.isEmpty, !file.name.hasPrefix("."),
                      !file.name.contains("/"), !file.name.contains("\\"), file.bytes > 0,
                      file.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
                    throw VaultError.message("Invalid starter file")
                }
            }
        }
        return models
    }
}

/// A bounded-memory download. Partial files survive cancellation/relaunch. The
/// model becomes selectable only after every size/hash and the folder validate.
public enum StarterModelInstaller {
    public static func verified(_ url: URL, file: StarterModel.File) throws -> Bool {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath:url.path)[.size]) as? Int64,
              size == file.bytes else { return false }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            digest.update(data: chunk)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined() == file.sha256
    }

    @discardableResult
    public static func install(_ model: StarterModel, root: URL, notices: URL,
                               baseURL: URL = URL(string: "https://huggingface.co")!,
                               progress: @escaping @Sendable (Int64, Int64, String) -> Void) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(model.folder)
        guard !fm.fileExists(atPath: destination.path) else {
            throw VaultError.message("This model folder already exists. Import it or choose the installed model; existing weights will not be overwritten.")
        }
        let staging = root.appendingPathComponent(".download-\(model.folder)-\(model.revision)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let available = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
        let already = model.files.reduce(Int64(0)) { total, file in
            total + Int64((try? staging.appendingPathComponent(file.name).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        guard available > max(0, model.bytes - already) + 256 * 1024 * 1024 else {
            throw VaultError.message("Free more storage before installing this model. It needs \(String(format: "%.1f", Double(model.bytes) / 1e9)) GB plus a little space for setup.")
        }
        var completed: Int64 = 0
        for file in model.files {
            try Task.checkCancellation()
            let target = staging.appendingPathComponent(file.name)
            if try verified(target, file: file) {
                completed += file.bytes
                progress(completed, model.bytes, file.name)
                continue
            }
            // A full-sized file with a failed hash is discarded, never resumed.
            if let size = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               size >= file.bytes { try fm.removeItem(at: target) }
            let remote = baseURL.appendingPathComponent(model.repository)
                .appendingPathComponent("resolve").appendingPathComponent(model.revision)
                .appendingPathComponent(file.name)
            let previous = completed
            let transfer = ResumableModelFile(url: remote, target: target, expected: file.bytes) { bytes in
                progress(previous + bytes, model.bytes, file.name)
            }
            try await withTaskCancellationHandler(operation: { try await transfer.run() }, onCancel: { transfer.cancel() })
            progress(completed + file.bytes, model.bytes, "Verifying \(file.name)…")
            guard try verified(target, file: file) else {
                try? fm.removeItem(at: target)
                throw VaultError.message("The downloaded \(file.name) failed its checksum. Retry to fetch a clean copy.")
            }
            completed += file.bytes
        }
        try Task.checkCancellation()
        for (source, name) in [("Qwen-LICENSE.txt", "LICENSE"), ("Qwen-NOTICE.txt", "NOTICE")] {
            let data = try Data(contentsOf: notices.appendingPathComponent(source))
            try data.write(to: staging.appendingPathComponent(name), options: .atomic)
        }
        let manifest: [String: Any] = ["name": model.name, "precision": model.precision,
                                     "repository": model.repository, "revision": model.revision,
                                     "recommended": model.id == "qwen-small"]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: staging.appendingPathComponent("vault-model.json"), options: .atomic)
        _ = try ModelLibrary.inspect(staging)
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: destination)
        progress(model.bytes, model.bytes, "Ready offline")
        return destination
    }
}

private final class ResumableModelFile: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let url: URL, target: URL, expected: Int64
    private let progress: @Sendable (Int64) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var continuation: CheckedContinuation<Void, Error>?
    private var received: Int64 = 0
    private var failure: Error?
    private let lock = NSLock()
    private var cancelled = false

    init(url: URL, target: URL, expected: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.url = url; self.target = target; self.expected = expected; self.progress = progress
    }
    func cancel() { lock.lock(); cancelled = true; let current = task; lock.unlock(); current?.cancel() }
    func run() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock(); defer { lock.unlock() }
            if cancelled { continuation.resume(throwing: CancellationError()); return }
            self.continuation = continuation
            received = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            var request = URLRequest(url: url)
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if received > 0 { request.setValue("bytes=\(received)-", forHTTPHeaderField: "Range") }
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 12 * 60 * 60
            config.urlCache = nil
            let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
            session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            task = session!.dataTask(with: request)
            task!.resume()
        }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        do {
            guard let http = response as? HTTPURLResponse else { throw VaultError.message("Invalid model download response") }
            if http.statusCode == 200 { received = 0 }
            else if http.statusCode == 206 {
                guard let range = http.value(forHTTPHeaderField: "Content-Range"),
                      range == "bytes \(received)-\(expected - 1)/\(expected)" else {
                    throw VaultError.message("Server returned an incorrect resume range. Retry the download.")
                }
            } else { throw VaultError.message("Download returned HTTP \(http.statusCode). Check your connection and retry.") }
            if !FileManager.default.fileExists(atPath: target.path) { FileManager.default.createFile(atPath: target.path, contents: nil) }
            handle = try FileHandle(forWritingTo: target)
            try handle!.truncate(atOffset: UInt64(received))
            try handle!.seek(toOffset: UInt64(received))
            completionHandler(.allow)
        } catch { failure = error; completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            guard received + Int64(data.count) <= expected, let handle else {
                throw VaultError.message("Download exceeded its expected size")
            }
            try handle.write(contentsOf: data)
            received += Int64(data.count)
            progress(received)
        } catch { failure = error; dataTask.cancel() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        try? handle?.close(); handle = nil
        lock.lock(); let cancelled = self.cancelled; lock.unlock()
        let resultError = failure ?? (cancelled ? CancellationError() : error)
            ?? (received == expected ? nil : VaultError.message("The download was interrupted. Tap Resume to continue."))
        if let resultError { continuation?.resume(throwing: resultError) } else { continuation?.resume() }
        continuation = nil
        session.finishTasksAndInvalidate()
        self.session = nil
    }
}
