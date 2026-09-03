import Darwin
import Foundation

/// One `mlx_lm.server` subprocess.
///
/// `LocalLLMEngine` owns exactly one of these and brings it up on demand. The
/// server is not pinned to a model: it loads whatever model each request names
/// and keeps it resident, so switching models in Settings needs no restart.
@MainActor
final class LocalLLMServer {
    private let paths: LocalLLMPaths
    private var process: Process?
    private var errorPipe: Pipe?
    private var stderrTail = RingBuffer(capacity: 40)

    private(set) var baseURL: URL?

    /// The most recent line the server wrote to stderr, for the Settings screen
    /// to show while a model downloads. huggingface_hub logs progress here.
    private(set) var lastProgressLine: String?

    init(paths: LocalLLMPaths) {
        self.paths = paths
    }

    var isRunning: Bool { process?.isRunning == true && baseURL != nil }

    /// Starts the server and returns once it answers `GET /v1/models`, or throws
    /// with whatever it printed on the way out.
    func start() async throws {
        if isRunning { return }
        stop()

        let port = try PortFinder.free()
        let url = URL(string: "http://127.0.0.1:\(port)")!

        let process = Process()
        process.executableURL = paths.pythonExecutable
        // `-m mlx_lm.server` is the entry point documented in mlx-lm's SERVER.md
        // and is stable across the versions that also expose the `mlx_lm server`
        // subcommand.
        process.arguments = ["-m", "mlx_lm.server", "--host", "127.0.0.1", "--port", "\(port)"]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HOME"] = paths.huggingFaceHome.path
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        let errorPipe = Pipe()
        process.standardError = errorPipe
        // stdout is not read; leaving it on a pipe nobody drains would let a
        // chatty run fill the buffer and wedge the process.
        process.standardOutput = FileHandle.nullDevice
        self.errorPipe = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let text = String(decoding: chunk, as: UTF8.self)
            Task { @MainActor [weak self] in self?.absorb(stderr: text) }
        }

        try FileManager.default.createDirectory(at: paths.huggingFaceHome, withIntermediateDirectories: true)
        do {
            try process.run()
        } catch {
            throw LocalLLMServerError.launchFailed(error.localizedDescription)
        }

        self.process = process
        writePID(process.processIdentifier)

        do {
            try await waitUntilReady(at: url, process: process)
        } catch {
            stop()
            throw error
        }
        baseURL = url
    }

    func stop() {
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe = nil
        if let process, process.isRunning {
            // SIGTERM, then SIGKILL if it is still there a moment later.
            process.terminate()
            let pid = process.processIdentifier
            Task.detached {
                try? await Task.sleep(for: .seconds(3))
                kill(pid, SIGKILL)
            }
        }
        process = nil
        baseURL = nil
        clearPID()
    }

    private func waitUntilReady(at url: URL, process: Process) async throws {
        let deadline = Date().addingTimeInterval(30)
        let probe = url.appending(path: "v1/models")
        while Date() < deadline {
            if !process.isRunning {
                throw LocalLLMServerError.exitedEarly(stderrTail.joined())
            }
            var request = URLRequest(url: probe)
            request.timeoutInterval = 3
            // Any HTTP reply means it is listening. Started without `--model`
            // the server has no model list to return 200 for, but it is up.
            if let (_, response) = try? await URLSession.shared.data(for: request),
               response is HTTPURLResponse {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw LocalLLMServerError.startupTimedOut(stderrTail.joined())
    }

    private func absorb(stderr text: String) {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            stderrTail.append(trimmed)
            lastProgressLine = trimmed
        }
    }

    private func writePID(_ pid: Int32) {
        try? FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try? "\(pid)".write(to: paths.serverPID, atomically: true, encoding: .utf8)
    }

    private func clearPID() {
        try? FileManager.default.removeItem(at: paths.serverPID)
    }
}

enum LocalLLMServerError: LocalizedError {
    case launchFailed(String)
    case exitedEarly(String)
    case startupTimedOut(String)
    case noFreePort

    var errorDescription: String? {
        switch self {
        case .launchFailed(let detail):
            "Could not start the local model server: \(detail)"
        case .exitedEarly(let log):
            "The local model server stopped right after starting.\(Self.tail(log))"
        case .startupTimedOut(let log):
            "The local model server did not become ready in time.\(Self.tail(log))"
        case .noFreePort:
            "Could not find a free local port for the model server."
        }
    }

    private static func tail(_ log: String) -> String {
        let trimmed = log.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : " It said: \(trimmed.suffix(300))"
    }
}

/// A fixed-size window over the most recent lines, for surfacing a subprocess's
/// last words without holding all of its output.
private struct RingBuffer {
    private var lines: [String] = []
    private let capacity: Int

    init(capacity: Int) { self.capacity = capacity }

    mutating func append(_ line: String) {
        lines.append(line)
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    func joined() -> String { lines.joined(separator: "\n") }
}

/// Asks the kernel for an unused loopback TCP port by binding one and reading it
/// back. There is a small window between closing the socket here and the server
/// binding it; a collision just surfaces as a startup error and a retry.
enum PortFinder {
    static func free() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LocalLLMServerError.noFreePort }
        defer { close(fd) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw LocalLLMServerError.noFreePort }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        var assigned = sockaddr_in()
        let named = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else { throw LocalLLMServerError.noFreePort }
        return UInt16(bigEndian: assigned.sin_port)
    }
}
