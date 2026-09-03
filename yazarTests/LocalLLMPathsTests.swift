import Foundation
import Testing
@testable import yazar

@Suite("Local LLM paths")
struct LocalLLMPathsTests {
    @Test("Every path sits under the given root")
    func layoutUnderRoot() {
        let root = URL(fileURLWithPath: "/tmp/yazar-llm-test")
        let paths = LocalLLMPaths(root: root)

        for url in [paths.uv, paths.venv, paths.pythonExecutable, paths.huggingFaceHome,
                    paths.installMarker, paths.serverPID, paths.binDirectory] {
            #expect(url.path.hasPrefix(root.path + "/"))
        }
    }

    @Test("The Python executable is inside the venv")
    func pythonInsideVenv() {
        let paths = LocalLLMPaths(root: URL(fileURLWithPath: "/tmp/yazar-llm-test"))
        #expect(paths.pythonExecutable.path.hasPrefix(paths.venv.path + "/"))
    }

    @Test("The default root is under Application Support/Yazar")
    func defaultRoot() {
        #expect(LocalLLMPaths.defaultRoot.path.contains("Application Support/Yazar/llm"))
    }
}
