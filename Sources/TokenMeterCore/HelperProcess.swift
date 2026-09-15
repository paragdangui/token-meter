import Foundation
import Darwin

/// Owns only processes launched by this app. No provider stderr is logged.
public final class HelperProcesses: @unchecked Sendable {
    public static let shared = HelperProcesses()
    private let lock = NSLock()
    private var processes: [UUID: Process] = [:]
    private var stopped = false
    public init() {}
    func launch(_ process: Process) throws -> UUID {
        lock.lock(); defer { lock.unlock() }
        guard !stopped else { throw CancellationError() }
        try process.run()
        let id = UUID(); processes[id] = process
        return id
    }
    func remove(_ id: UUID) { lock.lock(); processes[id] = nil; lock.unlock() }
    public func stop() {
        lock.lock(); stopped = true
        let owned = Array(processes.values); lock.unlock()
        for process in owned where process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

final class HelperProcess {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private let deadline: Date
    private let owner: HelperProcesses
    private var id: UUID?
    init(path: String, arguments: [String], timeout: TimeInterval, owner: HelperProcesses = .shared) throws {
        self.owner = owner; deadline = Date().addingTimeInterval(timeout)
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        id = try owner.launch(process)
        // Close parent copies of child endpoints so EOF is observable.
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        // A helper that exits early must surface as a write error, not a SIGPIPE that kills the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }
    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
        if let id { owner.remove(id); self.id = nil }
    }
    deinit { if id != nil { close() } }
    func send(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message) + Data([10])
        do { try input.fileHandleForWriting.write(contentsOf: data) }
        catch { throw UsageFailure.unavailable("Codex helper exited.") }
    }
    private func readChunk() throws -> Data? {
        let fd = output.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&descriptor, 1, 100)
            if result < 0 { if errno == EINTR { continue }; throw UsageFailure.unavailable("Helper read failed.") }
            if result == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count > 0 { return Data(bytes.prefix(count)) }
            if count == 0 { return nil }
            if errno != EAGAIN && errno != EINTR { throw UsageFailure.unavailable("Helper read failed.") }
        }
        throw UsageFailure.timeout
    }
    func response(id: Int) throws -> [String: Any] {
        while true {
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]; buffer.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? Int == id else { continue }
                if let error = object["error"] as? [String: Any] {
                    let code = error["code"] as? Int
                    let message = (error["message"] as? String ?? "").lowercased()
                    if code == 401 || message.contains("unauthorized") || message.contains("not authenticated") || message.contains("not logged") {
                        throw UsageFailure.signedOut
                    }
                    if code == 429 || message.contains("429") || message.contains("too many requests") {
                        let details = error["data"] as? [String: Any]
                        let seconds = (details?["retryAfterSeconds"] as? NSNumber)?.stringValue
                        let header = details?["retryAfter"] as? String ?? seconds
                        throw UsageFailure.throttled(UsageParsing.retryDate(header, now: Date()))
                    }
                    throw UsageFailure.unavailable("Codex usage request failed. Will retry.")
                }
                guard let result = object["result"] as? [String: Any] else { throw UsageFailure.unavailable("Unexpected Codex response.") }
                return result
            }
            guard let chunk = try readChunk() else { throw UsageFailure.unavailable("Codex helper exited.") }
            buffer.append(chunk)
            guard buffer.count < 2_000_000 else { throw UsageFailure.unavailable("Unexpected helper output.") }
        }
    }
    func readToEnd() throws -> Data {
        var data = Data()
        while let chunk = try readChunk() {
            data.append(chunk)
            guard data.count < 1_000_000 else { throw UsageFailure.unavailable("Unexpected credential response.") }
        }
        return data
    }
}

func blocking<T>(_ operation: @escaping () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .utility).async {
            do { continuation.resume(returning: try operation()) }
            catch { continuation.resume(throwing: error) }
        }
    }
}
