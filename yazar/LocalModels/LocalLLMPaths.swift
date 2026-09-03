import Foundation

/// Where the local model engine keeps everything it downloads.
///
/// One directory, `~/Library/Application Support/Yazar/llm`, so uninstalling is
/// removing a folder and nothing on the user's machine outside it is touched.
/// Modelled on `MeetingStore.defaultRoot`.
struct LocalLLMPaths: Sendable {
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? Self.defaultRoot
    }

    static var defaultRoot: URL {
        URL.applicationSupportDirectory
            .appending(path: "Yazar", directoryHint: .isDirectory)
            .appending(path: "llm", directoryHint: .isDirectory)
    }

    /// The `uv` binary the installer downloads. Everything else is created by
    /// running it.
    var uv: URL {
        root.appending(path: "bin/uv", directoryHint: .notDirectory)
    }

    /// The virtual environment `uv` builds, with its own managed Python.
    var venv: URL {
        root.appending(path: "venv", directoryHint: .isDirectory)
    }

    var pythonExecutable: URL {
        venv.appending(path: "bin/python", directoryHint: .notDirectory)
    }

    /// Passed to the server as `HF_HOME`, so model blobs land here and not in the
    /// user's shared `~/.cache/huggingface`, and "Remove downloaded models" can
    /// reclaim them without disturbing anything else.
    var huggingFaceHome: URL {
        root.appending(path: "huggingface", directoryHint: .isDirectory)
    }

    /// Written once the venv has `mlx-lm` in it. Its contents name the version,
    /// so a future upgrade can compare rather than reinstall blindly.
    var installMarker: URL {
        root.appending(path: ".installed", directoryHint: .notDirectory)
    }

    /// The last server subprocess's pid, so a copy orphaned by a crash can be
    /// killed on the next launch.
    var serverPID: URL {
        root.appending(path: "server.pid", directoryHint: .notDirectory)
    }

    var binDirectory: URL {
        root.appending(path: "bin", directoryHint: .isDirectory)
    }
}
