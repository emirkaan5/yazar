# Local LLM engine (mlx-lm) for Yazar — as built

Branch `feature/local-llm`, rebased directly onto `main`. One commit.

## Context

Meeting-notes generation always uploaded the full transcript to OpenRouter — a
transcript of other people who were never asked. This adds a second
`LanguageModelClient` that runs open-weight models on this Mac with Apple's
`mlx-lm`, selectable per a new setting. The engine is provider-agnostic on
purpose: `docs/roadmap.md` item 1 (dictation post-processing) is a future third
caller, not new infrastructure.

Decisions (with the owner): bundled `uv` downloaded on demand (no system Python,
nothing outside `~/Library/Application Support/Yazar/llm/` touched); a dedicated
"Local Models" settings page; an explicit Install button; default model
`mlx-community/gemma-3-12b-it-4bit`. Transcription untouched.

## Shape

`LanguageModelClient` (`yazar/Notes/`) was already the provider-agnostic seam.

- **`yazar/Notes/LanguageModelProvider.swift`** — `.openRouter` / `.local`,
  mirrors `TranscriptionProvider`. `makeClient(settings:engine:)` returns an
  `OpenRouterClient` or, for `.local`, `engine.client(for: settings.localModel)`.
- **`yazar/LocalModels/`**
  - `LocalLLMPaths` — on-disk layout (`bin/uv`, `venv/`, `huggingface/` as
    `HF_HOME`, `.installed` marker, `server.pid`, redirected `python/` + `cache/`).
  - `ProcessRunner` — run a short command to completion, capture output.
  - `LocalLLMInstaller` — pinned `uv` 0.12.8 (SHA-256 verified) → `uv venv
    --python 3.12` → `uv pip install mlx-lm==0.31.3` → marker with the resolved
    version.
  - `LocalLLMServer` — one `python -m mlx_lm.server --host 127.0.0.1 --port
    <free>` subprocess, `HF_HOME` set, health = any HTTP reply on `/v1/models`
    (the server starts with no `--model` and loads per request), stderr tail
    kept for errors + download-progress display, SIGTERM→SIGKILL stop, pid file.
  - `LocalLLMClient` — `nonisolated struct`, OpenAI request body, loopback URL,
    no auth, its own simple response decoder, 600 s timeout (3600 s cold).
  - `LocalLLMEngine` — `@MainActor @Observable` single owner: `installState`,
    `modelState`, `diskUsage`; `install` / `cancelInstall` / `uninstall` /
    `removeDownloadedModels`; `prepare(model:)` warms the server with a 1-token
    completion so downloads happen deliberately in Settings; `client(for:)`
    brings the server up and resets a 10-minute idle-shutdown timer; kills an
    orphaned server pid on init; `shutdown()` on quit.
  - `SuggestedLocalModel` — gemma-3-12b-it-4bit (default), Qwen3-8B-4bit,
    Qwen3-4B-Instruct-2507-4bit.
- **Settings** — `Settings.languageModelProvider` + `localModel`;
  `AppPage.localModels`; `LocalModelsSettingsView` (Engine / Model / Storage
  sections). `MeetingsSettingsView` gained a `localLLM` and its Notes "Privacy"
  row now reflects whichever engine is selected; the OpenRouter model row hides
  when Local is chosen. `NotesComposer` (DEBUG) and `TranscriptNotesSection`
  take the engine through.
- **Wiring** — `AppDelegate` owns one `LocalLLMEngine`, passes it to
  `MeetingNotesMaker` and `YazarView`; `applicationWillTerminate` calls
  `engine.shutdown()`. Both note-making call sites do `provider.makeClient(...)`
  inside their existing `Task`; the `LocalLLM*Error` types conform to
  `LocalizedError` so the current failure display needs no change.

## Notes

- Server invocation verified against mlx-lm's `server.py`: `--model` is
  optional, per-request model loading works, `--host`/`--port` exist.
- `mlx-lm` pinned to an exact version; the marker records the resolved version.
- No entitlement / sandbox / `project.pbxproj` changes. Child executables
  (`uv`, managed `python`) are separate processes, not dylibs loaded into
  Yazar, so hardened-runtime library validation does not apply. The installer
  strips the quarantine xattr from what it downloads.
- `OpenRouterNoteMaker` was **not** renamed (it already takes any
  `LanguageModelClient`); deferred to keep the diff focused.
- Install progress is step-level, no byte fractions.

## Verification

- `xcodebuild ... build`, `... analyze`, `... test` — green on top of `main`.
- 18 new tests: `LocalLLMClientTests` (URLProtocol stub — content, service
  error, empty choices, truncation, blank model), `LocalLLMPathsTests`,
  `LanguageModelProviderTests`, `SuggestedLocalModelTests`, `LocalLLMEngineTests`
  (install-state from marker, `client(for:)` guard, stale-pid kill on init).
- Manual, on a real Mac (not possible headlessly): install flow → "Installed";
  pick a model → Download → "Downloaded"; Notes with engine Local → notes
  return, `pgrep -f mlx_lm` shows the server, no egress; 10-minute idle → server
  exits, next request respawns; quit mid-serve → child gone; relaunch with a
  stale child → killed on init; "Remove Models" / "Remove" reclaim disk.

## Follow-ups

- Rename `OpenRouterNoteMaker` → `LanguageModelNoteMaker`.
- Real byte-level download progress (parse huggingface_hub / tqdm stderr).
- `gemma-3-*` mlx repos are `mlx-vlm`-converted; confirm `mlx_lm.server` loads
  the default as a text model on a real run, else make `Qwen3-8B-4bit` the
  default.
- The System Audio Recording permission-prompt work from a concurrent session
  is **not** in this branch: it depends on the Core Audio process-tap capture
  engine, and `main` is still on ScreenCaptureKit. It belongs with that engine's
  own merge.
