import Darwin
import Foundation

/// Runs a short-lived command to completion and hands back what it printed.
///
/// For the install steps only — `uv`, `tar`. The model server is long-running
/// and streams its output, so it has its own type in `LocalLLMServer`.
enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let standardOutput: String
        let standardError: String

        var succeeded: Bool { status == 0 }

        /// The line most likely to explain a failure: the last non-empty line of
        /// stderr, or of stdout if stderr was silent.
        var failureLine: String {
            let source = standardError.isEmpty ? standardOutput : standardError
            return source
                .split(whereSeparator: \.isNewline)
                .last
                .map(String.init)?
                .trimmingCharacters(in: .whitespaces)
                ?? "no output"
        }
    }

    /// Cancellation terminates the child before rethrowing.
    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let pid = process.processIdentifier

        // Read both pipes concurrently so a large stream on either cannot fill a
        // pipe buffer and deadlock the child.
        async let outData = readToEnd(outPipe.fileHandleForReading)
        async let errData = readToEnd(errPipe.fileHandleForReading)

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                process.terminationHandler = { _ in continuation.resume() }
            }
        } onCancel: {
            kill(pid, SIGTERM)
        }

        let (out, err) = await (outData, errData)
        try Task.checkCancellation()
        return Result(
            status: process.terminationStatus,
            standardOutput: String(decoding: out, as: UTF8.self),
            standardError: String(decoding: err, as: UTF8.self)
        )
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = (try? handle.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }
}
