import CryptoKit
import Foundation

/// Sets up the `mlx-lm` runtime under `LocalLLMPaths.root`, one step at a time,
/// reporting progress as it goes.
///
/// Split from `LocalLLMEngine` the way `AppleSpeechTranscriber` (the work) is
/// split from `AppleSpeechModel` (the state a screen reads): this type knows the
/// steps, the engine knows what state to be in while they run.
struct LocalLLMInstaller {
    enum Step: Sendable, Equatable {
        case downloadingRuntime
        case installingPython
        case installingMLX
        case finalizing

        var label: String {
            switch self {
            case .downloadingRuntime: "Downloading the package manager"
            case .installingPython: "Installing Python"
            case .installingMLX: "Installing mlx-lm"
            case .finalizing: "Finishing up"
            }
        }
    }

    struct Progress: Sendable, Equatable {
        var step: Step
    }

    // Pinned. A newer uv or mlx-lm is a deliberate edit here, not a silent
    // upgrade on the user's next install.
    static let uvVersion = "0.12.8"
    static let uvArchiveSHA256 = "8ce083658dbff20143607ca7af8e0c1d64b6fd7bf03a5cdcb62bf3d47d991b5f"
    static let mlxLMRequirement = "mlx-lm==0.31.3"

    private static var uvArchiveURL: URL {
        URL(string: "https://github.com/astral-sh/uv/releases/download/\(uvVersion)/uv-aarch64-apple-darwin.tar.gz")!
    }

    let paths: LocalLLMPaths

    /// Runs every step. Returns the resolved `mlx_lm` version string, which the
    /// engine writes into the install marker.
    func install(onProgress: (Progress) -> Void) async throws -> String {
        try FileManager.default.createDirectory(at: paths.binDirectory, withIntermediateDirectories: true)

        onProgress(Progress(step: .downloadingRuntime))
        try await downloadUV()

        onProgress(Progress(step: .installingPython))
        try await createVenv()

        onProgress(Progress(step: .installingMLX))
        try await installMLXLM()

        onProgress(Progress(step: .finalizing))
        let version = try await resolvedMLXLMVersion()
        return version
    }

    /// uv is managed under our own root, not the user's `~/.local/share/uv`, so
    /// that removing `LocalLLMPaths.root` removes everything.
    private var toolEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["UV_PYTHON_INSTALL_DIR"] = paths.root.appending(path: "python").path
        environment["UV_CACHE_DIR"] = paths.root.appending(path: "cache").path
        environment["UV_NO_MODIFY_PATH"] = "1"
        environment["HF_HOME"] = paths.huggingFaceHome.path
        return environment
    }

    private func downloadUV() async throws {
        let (tempURL, response) = try await URLSession.shared.download(from: Self.uvArchiveURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
            throw LocalLLMInstallError.download("uv \(Self.uvVersion) could not be downloaded.")
        }

        let data = try Data(contentsOf: tempURL)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        guard hex == Self.uvArchiveSHA256 else {
            throw LocalLLMInstallError.checksumMismatch(expected: Self.uvArchiveSHA256, actual: hex)
        }

        // The archive holds `uv-aarch64-apple-darwin/uv` and `.../uvx`. Take just
        // `uv`, flattening the leading directory.
        let extractDir = paths.root.appending(path: "uv-extract", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: extractDir)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: extractDir) }

        let tar = try await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xzf", tempURL.path, "-C", extractDir.path, "--strip-components=1"]
        )
        guard tar.succeeded else {
            throw LocalLLMInstallError.extraction(tar.failureLine)
        }

        let extractedUV = extractDir.appending(path: "uv", directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: extractedUV.path) else {
            throw LocalLLMInstallError.extraction("the uv binary was not in the archive")
        }
        try? FileManager.default.removeItem(at: paths.uv)
        try FileManager.default.moveItem(at: extractedUV, to: paths.uv)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.uv.path)
        await stripQuarantine(paths.uv)
    }

    private func createVenv() async throws {
        try? FileManager.default.removeItem(at: paths.venv)
        let result = try await ProcessRunner.run(
            paths.uv,
            arguments: ["venv", "--python", "3.12", paths.venv.path],
            environment: toolEnvironment
        )
        guard result.succeeded else {
            throw LocalLLMInstallError.step("creating the Python environment", result.failureLine)
        }
        await stripQuarantine(paths.pythonExecutable)
    }

    private func installMLXLM() async throws {
        let result = try await ProcessRunner.run(
            paths.uv,
            arguments: [
                "pip", "install",
                "--python", paths.pythonExecutable.path,
                Self.mlxLMRequirement,
            ],
            environment: toolEnvironment
        )
        guard result.succeeded else {
            throw LocalLLMInstallError.step("installing mlx-lm", result.failureLine)
        }
    }

    private func resolvedMLXLMVersion() async throws -> String {
        let result = try await ProcessRunner.run(
            paths.pythonExecutable,
            arguments: ["-c", "import mlx_lm; print(mlx_lm.__version__)"],
            environment: toolEnvironment
        )
        guard result.succeeded else {
            throw LocalLLMInstallError.step("verifying the install", result.failureLine)
        }
        let version = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? "unknown" : version
    }

    /// A downloaded executable can carry `com.apple.quarantine`, which makes
    /// Gatekeeper refuse to exec it. Best effort — a missing attribute makes
    /// `xattr` exit nonzero and that is fine.
    private func stripQuarantine(_ url: URL) async {
        _ = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-d", "com.apple.quarantine", url.path]
        )
    }
}

enum LocalLLMInstallError: LocalizedError {
    case download(String)
    case checksumMismatch(expected: String, actual: String)
    case extraction(String)
    case step(String, String)

    var errorDescription: String? {
        switch self {
        case .download(let detail):
            detail
        case .checksumMismatch:
            "The downloaded package manager did not match its expected checksum and was discarded."
        case .extraction(let detail):
            "The package manager archive could not be unpacked: \(detail)."
        case .step(let what, let detail):
            "Failed while \(what): \(detail)"
        }
    }
}
