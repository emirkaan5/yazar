import AppKit
import Darwin
import Foundation
import Observation

/// The one owner of the local `mlx-lm` runtime: its install state, its server
/// subprocess, and the lifecycle around both.
///
/// Shaped after `AppleSpeechModel` — a state enum a settings screen reads, work
/// done in cancellable tasks — but bigger, because unlike a system framework
/// this runtime is downloaded, run as a child process, and has to be cleaned up.
@MainActor
@Observable
final class LocalLLMEngine {
    enum InstallState: Equatable {
        case notInstalled
        case installing(LocalLLMInstaller.Progress)
        case installed(version: String)
        case failed(String)
    }

    /// State of the *currently selected* model — whether its weights are on disk
    /// and the server has loaded them.
    enum ModelState: Equatable {
        case notDownloaded
        case downloading(String?)
        case ready
        case failed(String)
    }

    private(set) var installState: InstallState
    private(set) var modelState: ModelState = .notDownloaded
    /// Recomputed by `refreshDiskUsage()`; bytes under `LocalLLMPaths.root`.
    private(set) var diskUsage: Int64 = 0

    private let paths: LocalLLMPaths
    private let idleTimeout: Duration
    private var server: LocalLLMServer?
    private var startTask: Task<LocalLLMServer, any Error>?
    private var installTask: Task<Void, Never>?
    private var prepareTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    /// The model the running server has actually served at least once.
    private var warmModel: String?

    init(paths: LocalLLMPaths = LocalLLMPaths(), idleTimeout: Duration = .seconds(600)) {
        self.paths = paths
        self.idleTimeout = idleTimeout
        self.installState = Self.detectInstallState(paths: paths)
        Self.killOrphanedServer(paths: paths)
    }

    var isInstalled: Bool {
        if case .installed = installState { return true }
        return false
    }

    var isInstalling: Bool {
        if case .installing = installState { return true }
        return false
    }

    // MARK: Install

    func install() {
        guard !isInstalling else { return }
        installState = .installing(LocalLLMInstaller.Progress(step: .downloadingRuntime))
        let installer = LocalLLMInstaller(paths: paths)
        let paths = paths
        installTask = Task { [weak self] in
            do {
                let version = try await installer.install { progress in
                    self?.installState = .installing(progress)
                }
                try Task.checkCancellation()
                try Self.writeMarker(version, paths: paths)
                guard let self else { return }
                installState = .installed(version: version)
                refreshModelState(for: nil)
                refreshDiskUsage()
            } catch is CancellationError {
                self?.installState = .notInstalled
            } catch {
                self?.installState = .failed(error.localizedDescription)
            }
        }
    }

    func cancelInstall() {
        installTask?.cancel()
        installTask = nil
        if isInstalling { installState = .notInstalled }
    }

    /// Removes the entire runtime, models included. The server is stopped first.
    func uninstall() {
        shutdown()
        try? FileManager.default.removeItem(at: paths.root)
        warmModel = nil
        installState = .notInstalled
        modelState = .notDownloaded
        refreshDiskUsage()
    }

    /// Removes downloaded model weights but keeps the runtime installed.
    func removeDownloadedModels() {
        shutdown()
        try? FileManager.default.removeItem(at: paths.huggingFaceHome)
        warmModel = nil
        modelState = .notDownloaded
        refreshDiskUsage()
    }

    // MARK: Model preparation

    /// Brings a model fully online — server up, weights downloaded, loaded into
    /// memory — with progress, so Settings can do it deliberately instead of the
    /// first notes request stalling for ten minutes behind a download.
    func prepare(model: String) {
        guard isInstalled else {
            modelState = .failed(LocalLLMError.engineNotInstalled.localizedDescription)
            return
        }
        prepareTask?.cancel()
        modelState = .downloading(nil)
        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                let server = try await runningServer()
                let progressPoll = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard let self else { return }
                        if case .downloading = self.modelState {
                            self.modelState = .downloading(server.lastProgressLine)
                        }
                    }
                }
                defer { progressPoll.cancel() }

                var warmup = LocalLLMClient(baseURL: server.baseURL!, model: model)
                warmup.timeout = 3600
                warmup.maxOutputTokens = 1
                _ = try await warmup.complete(system: "You are a test.", user: "Reply with 'ok'.", expectsJSON: false)
                try Task.checkCancellation()
                self.warmModel = model
                self.modelState = .ready
                self.refreshDiskUsage()
            } catch is CancellationError {
                self.refreshModelState(for: model)
            } catch {
                self.modelState = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-reads whether `model`'s weights are on disk. Pass nil to check against
    /// nothing in particular (used right after install).
    func refreshModelState(for model: String?) {
        guard isInstalled else { modelState = .notDownloaded; return }
        if let model, warmModel == model, server?.isRunning == true {
            modelState = .ready
        } else if let model, isModelDownloaded(model) {
            modelState = .ready
        } else {
            modelState = .notDownloaded
        }
    }

    // MARK: Serving

    /// A client bound to a running server for `model`. Throws before any request
    /// is sent if the engine is not installed.
    func client(for model: String) async throws -> LocalLLMClient {
        guard isInstalled else { throw LocalLLMError.engineNotInstalled }
        let server = try await runningServer()
        resetIdleTimer()

        var client = LocalLLMClient(baseURL: server.baseURL!, model: model)
        // A model whose weights are not on disk yet will be fetched inside this
        // first request; give that far more room than a warm generation needs.
        if warmModel != model, !isModelDownloaded(model) {
            client.timeout = 3600
        }
        return client
    }

    /// Called from `applicationWillTerminate`. `Process` children outlive the
    /// parent on macOS unless told otherwise.
    func shutdown() {
        startTask?.cancel()
        startTask = nil
        prepareTask?.cancel()
        idleTask?.cancel()
        idleTask = nil
        server?.stop()
        server = nil
    }

    private func runningServer() async throws -> LocalLLMServer {
        if let server, server.isRunning { return server }
        if let startTask { return try await startTask.value }

        let task = Task { [paths] () -> LocalLLMServer in
            let server = LocalLLMServer(paths: paths)
            try await server.start()
            return server
        }
        startTask = task
        defer { startTask = nil }
        do {
            let server = try await task.value
            self.server = server
            return server
        } catch {
            self.server = nil
            throw error
        }
    }

    private func resetIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self, idleTimeout] in
            try? await Task.sleep(for: idleTimeout)
            guard !Task.isCancelled, let self else { return }
            self.server?.stop()
            self.server = nil
            self.warmModel = nil
        }
    }

    // MARK: Disk

    func refreshDiskUsage() {
        let root = paths.root
        diskUsage = Self.directorySize(root)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([paths.root])
    }

    private func isModelDownloaded(_ model: String) -> Bool {
        // HF cache layout: <HF_HOME>/hub/models--<org>--<name>/snapshots/<rev>/
        let slug = "models--" + model.replacingOccurrences(of: "/", with: "--")
        let snapshots = paths.huggingFaceHome
            .appending(path: "hub", directoryHint: .isDirectory)
            .appending(path: slug, directoryHint: .isDirectory)
            .appending(path: "snapshots", directoryHint: .isDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: snapshots,
            includingPropertiesForKeys: nil
        ) else { return false }
        return !contents.isEmpty
    }

    // MARK: Statics

    private static func detectInstallState(paths: LocalLLMPaths) -> InstallState {
        guard FileManager.default.fileExists(atPath: paths.pythonExecutable.path),
              let version = try? String(contentsOf: paths.installMarker, encoding: .utf8)
        else { return .notInstalled }
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return .installed(version: trimmed.isEmpty ? "unknown" : trimmed)
    }

    private static func writeMarker(_ version: String, paths: LocalLLMPaths) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try version.write(to: paths.installMarker, atomically: true, encoding: .utf8)
    }

    private static func killOrphanedServer(paths: LocalLLMPaths) {
        guard let text = try? String(contentsOf: paths.serverPID, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        // Signal 0 tests for existence; a live pid here is from a crash, since a
        // clean stop clears the file.
        if kill(pid, 0) == 0 {
            kill(pid, SIGKILL)
        }
        try? FileManager.default.removeItem(at: paths.serverPID)
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
            )
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

enum LocalLLMError: LocalizedError {
    case engineNotInstalled

    var errorDescription: String? {
        switch self {
        case .engineNotInstalled:
            "Install the local model engine in Settings › Local Models to generate notes on this Mac."
        }
    }
}
