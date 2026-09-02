# Meeting Notes — Progress

Session log for the plan in `meeting-notes.md`. Written 1–2 September 2026.
Records what was decided, what is built, what is actually verified, and the
things that cost time and would cost it again.

## Decisions taken during the work

These refine the plan rather than restate it.

- **Meeting mode records system audio only.** The microphone is never opened, so
  there is no mixer, no clock drift between sources, and no contention with
  `Recorder`. Dictation stays usable during a meeting. The cost is that the
  user's own voice is absent from meeting transcripts.
- **Notes are OpenRouter-only for now.** The on-device Apple Foundation Models
  path is deferred. This removed map-reduce chunking and the chunk-boundary rule
  entirely, since an hour fits in one prompt.
- **No `NotesProvider` enum.** A one-case mirror of `TranscriptionProvider` would
  be shape without substance. `NoteMaker` and `Notes` are the seam a second
  provider slots into; `LanguageModelClient` sits underneath and knows nothing
  about notes, so roadmap item 1 reuses it.
- **No index file in the store.** The plan called for one. Enumerating meeting
  directories cannot disagree with itself, and an index would be a second place
  the truth lives.
- **Transcript and notes live inside `meeting.json`,** not as sibling files, so
  one atomic write keeps them consistent with the `state` field that doubles as
  the crash-recovery marker. Audio stays out of line, being large and binary.
- **`makeNotes(from: String)`, not `from: Transcript`.** Gap markers are inline
  text by the time a transcript reaches the note maker, so the wrapper would
  carry nothing.
- **Both segment end reasons produce a marker**, with different wording. A user
  stop reads as a pause (`[resumed after 4h]`); an interruption reads as missing
  audio (`[recording interrupted, up to 6 minutes not captured]`), because the
  meeting carried on without Yazar and the transcript has a hole the model
  cannot see.
- **One streaming entry point on `Transcriber`,** and dictation is expressed as a
  stream of one buffer rather than keeping a second analyzer setup beside it.
  Dictation keeps the `.transcription` preset; meetings use
  `.progressiveTranscription`, because only a meeting has a window showing the
  sentence being spoken. That preset difference is the only thing that separates
  the two paths.
- **Segments carry their own transcript, and `Meeting.transcript` is derived.**
  The stored string became `importedTranscript`, for text pasted or dropped in,
  and it still encodes under the old `transcript` key. Recorded meetings leave it
  empty and assemble from segments, which is the only place the gap markers can
  come from — a merged string has nowhere to put them.
- **Chunk boundaries are a plain clock for now.** Silence-based boundaries stay
  in phase 6 as planned. A silent chunk is not uploaded at all, though: that is a
  paid request that comes back as a hallucinated pleasantry.
- **The wait after the last sample is bounded** (180 s). A provider that never
  returns would otherwise wedge meeting mode until the app is relaunched.
- **Notes are made automatically when a recording stops,** by a
  `MeetingNotesMaker` that works on the stored record rather than on text a
  screen is holding. The same call backs the Make Notes button, so a failed
  attempt is a retry rather than a dead end. `makingNotes` joined the meeting
  states; `interrupted` outlives it, because that badge is about audio nobody
  captured. There is no setting to turn this off, so recording a meeting with an
  OpenRouter key present means its transcript is uploaded without a second
  press — worth revisiting if the on-device note path arrives.

## Where the phases stand

Branch `meeting-notes`, off `main` at 70c0095.

| Phase | State |
|---|---|
| 1. Notes from existing text | committed, verified on a real 50-minute transcript |
| 2. Storage and library | committed, verified: record persists with notes |
| 3. Capture | committed, **not manually tested** |
| 4. Long-form transcription | committed, **not manually tested** |
| 5. Meeting detection | not started |
| 6. Polish | not started |

Commits:

- `d40c84f` Plan detecting meetings and offering to record
- `2498482` Make notes from a transcript
- `1e11807` Keep meetings in a library
- `23beaab` Record a meeting's system audio
- `6271b85` Transcribe a meeting as it records
- `91820ab` Make notes when a meeting stops

The last three were split back out of one working tree, each built on
its own before it was committed.

Each was verified to build on its own; the shared files were rolled back to
their phase-1 shape and rebuilt before the first code commit.

## Verified, and not

Verified:

- Notes generated from a real 6,724-word meeting transcript, and the result
  stored and reloaded: 8 key points, 6 decisions, 7 action items.
- Single instance: a second process logs and exits, leaving one running.
- The store directory is created on launch.
- `SpeechAnalyzer` transcribed 50 minutes (2,996 s) of audio in one streaming
  pass, feeding buffers concurrently rather than buffering the file. This is the
  shape phase 4 needs, so the main unknown in that phase is largely retired.

Not verified:

- **Everything in phase 3.** No meeting has been recorded. `SCStream` audio-only
  capture, the Screen Recording prompt, the power assertion, and sleep handling
  are all untested. Testing needs the menu bar, which cannot be driven headlessly
  here.
- **Everything in phase 4 that needs a running meeting,** and the notes made at
  the end of one. The live Apple Speech transcript, the chunked OpenRouter path,
  the drain after stopping, and the automatic note generation have only been
  compiled. What was verified without a meeting: transcript assembly and its
  markers, records written before segment transcripts existing still decoding,
  and the chunker's boundaries, all exercised against the real types with
  `swiftc`.
- Any UI rendering. Screen capture and UI scripting are both blocked in this
  environment.

## Things that cost time

Worth knowing before they cost it again.

- **No signing certificate.** `xcodebuild` failed before compiling anything with
  `No "Mac Development" signing certificate`. The keychain has no codesigning
  identity. Debug builds here use `CODE_SIGN_IDENTITY="-"`. The real fix is
  creating an Apple Development certificate through Xcode's Accounts pane, which
  cannot be done headlessly.
- **TCC grants follow the code signature.** An ad-hoc signed build gets a new
  identity on every rebuild, so Accessibility and Screen Recording grants reset.
  A real certificate fixes this permanently.
- **Single instance affects development.** A build launched from Xcode exits when
  the installed copy is running. It logs why. Quit the menu bar copy first.
- **A build reported `BUILD SUCCEEDED` without relinking.** New code was absent
  from the running binary and the store directory silently never appeared.
  `touch`ing the sources and rebuilding fixed it. Suspect this when behaviour
  does not match the source.
- **`thinkingmachines/inkling:free` returns HTTP 403** — "only available on
  agentic harnesses". It cannot be called from Yazar at all.
- **Free models vary wildly.** Tested with the app's exact request shape:
  `minimax/minimax-m3:free` and `nvidia/nemotron-3-ultra-550b-a55b:free` both
  returned clean, schema-correct JSON. `google/gemma-4-31b-it:free` and
  `inclusionai/ling-3.0-flash-fin:free` both returned "Provider returned error".

## Bugs found and fixed in `OpenRouterClient`

All four surfaced only against a real transcript, and all four are the sort that
look like someone else's fault until the response is read.

1. **No `max_tokens`.** OpenRouter then reserves credit against the model's full
   64,000-token ceiling, which a key with a spending limit cannot afford. Now
   capped at 12,000.
2. **`error.metadata` discarded.** "Provider returned error" is a wrapper around
   an upstream failure and is a dead end without the provider name and raw text
   folded in.
3. **Non-optional `content`.** Reasoning models return `content: null` alongside
   `reasoning` and `refusal`, which decoded as "The data couldn't be read because
   it is missing". All three fields are optional now, and refusal, truncation,
   and reasoning-only each get their own sentence.
4. **Reasoning tokens count against `max_tokens`.** 4,000 was enough for clean
   synthetic text and not for real speech, which is why a synthetic reproduction
   passed while the real transcript failed.

## Current configuration

- Notes model: `nvidia/nemotron-3-ultra-550b-a55b:free`, stored in defaults under
  `notesModel`. The code default only applies to a fresh install.
- Transcription: unchanged.

## Next

1. Manually test phases 3 and 4, which is now one test end to end: start a
   meeting, play speech, watch the transcript appear in the Meetings window,
   stop, and confirm the meeting is filed with a duration, its text, and notes
   that arrive on their own. Worth watching for specifically: whether `SCStream`
   buffers keep arriving over a long session, and whether `SpeechAnalyzer` grows
   over an hour of streaming.
2. Phase 5, meeting detection.

Left alone deliberately, as planned: silence-based chunk boundaries, the audio
retention setting, and the per-meeting cost display are phase 6, and dictated
asides come after that. Resuming a stopped meeting is modelled but has no control
in the library yet, so nothing yet exercises the gap markers against a real
recording, and notes are not marked stale on resume.
