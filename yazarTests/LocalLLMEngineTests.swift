import Darwin
import Foundation
import Testing
@testable import yazar

@MainActor
@Suite("Local LLM engine")
struct LocalLLMEngineTests {
    private func makeRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "llm-engine-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("A bare root reads as not installed")
    func notInstalled() {
        let engine = LocalLLMEngine(paths: LocalLLMPaths(root: makeRoot()))
        #expect(engine.installState == .notInstalled)
        #expect(!engine.isInstalled)
    }

    @Test("A venv python plus a marker reads as installed at that version")
    func installedFromMarker() throws {
        let root = makeRoot()
        let paths = LocalLLMPaths(root: root)
        try FileManager.default.createDirectory(
            at: paths.pythonExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: paths.pythonExecutable.path, contents: Data())
        try "0.31.3\n".write(to: paths.installMarker, atomically: true, encoding: .utf8)

        let engine = LocalLLMEngine(paths: paths)
        #expect(engine.installState == .installed(version: "0.31.3"))
        #expect(engine.isInstalled)
    }

    @Test("client(for:) throws when not installed")
    func clientRequiresInstall() async {
        let engine = LocalLLMEngine(paths: LocalLLMPaths(root: makeRoot()))
        await #expect(throws: LocalLLMError.self) {
            _ = try await engine.client(for: "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        }
    }

    @Test("A stale server pid is killed on init")
    func killsOrphanedServer() async throws {
        let root = makeRoot()
        let paths = LocalLLMPaths(root: root)

        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        try sleeper.run()
        let pid = sleeper.processIdentifier
        try "\(pid)".write(to: paths.serverPID, atomically: true, encoding: .utf8)

        _ = LocalLLMEngine(paths: paths)

        // Give the signal a moment to land.
        for _ in 0..<20 where kill(pid, 0) == 0 {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(kill(pid, 0) != 0)
        #expect(!FileManager.default.fileExists(atPath: paths.serverPID.path))
        sleeper.terminate()
    }
}
