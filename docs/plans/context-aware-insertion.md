# Context-Aware Insertion Design Brief

Status: implemented September 1, 2026.

## What and why

Add local transcript fitting that reads the target's current text and selection through macOS Accessibility, then adjusts only the inserted transcript's boundary case, punctuation, and spacing. The design fights unknown unknowns: AX controls expose equivalent text state through incompatible representations, while the formatting rules depend on exact ordering and Unicode behavior that must not leak into `Yazar` or clipboard delivery.

## Current fit and constraints

- `Yazar` owns the dictation lifecycle and directly causes transcription and delivery.
- `Inserter` owns the reliable clipboard write and best-effort Command-V. Context failure must not change that contract.
- The project has no local formatter, AX text reader, proper-noun sources, or test target today.
- The roadmap puts generic local formatting before app-specific formatting. Generic rules therefore need one pure home that later app-specific policy can call or neighbor without changing AX capture or paste delivery.
- AX ranges use UTF-16 offsets. Only `NSString`/`NSRange` may split AX-provided contents; Swift `String.Index` must never consume those offsets.
- The target uses Main Actor default isolation. AX observation and lifecycle state stay on the main actor; the pure value and formatter types opt out with `nonisolated` where needed.

## Design comparison

The hard-to-reverse choice is where to place the seam between context capture, formatting, and delivery.

### Rejected: one stateful context-aware inserter

`ContextAwareInserter.beginDictation()` and `ContextAwareInserter.insert(_:)` would give `Yazar` the smallest call site, but one type would need to know AX tree recovery, formatting policy, clipboard failure semantics, and paste events. Tests for pure string behavior would sit behind AppKit state, and the roadmap's app-specific formatting would enlarge the same type. The interface looks deep while hiding unrelated responsibilities.

### Chosen: AX capture, pure fitting, existing delivery

`TextContextCapture` knows how target applications expose text, `TranscriptFitter` knows the local insertion rules, and `Inserter` keeps knowing only clipboard/paste delivery. `Yazar` makes the causal chain visible with direct calls and passes the stop-time snapshot into the transcription task. This uses two new concepts, but each removes a distinct body of knowledge from every other caller; no protocol, registry, or mock-only seam is needed.

## Shape

### `TextInsertionContext`

A small immutable value containing only the canonical formatting inputs:

```swift
nonisolated struct TextInsertionContext: Equatable, Sendable {
    let beforeText: String
    let selectedText: String
    let afterText: String
    let applicationBundleIdentifier: String?
}
```

It also owns a failable construction path from `contents` plus an `NSRange`, so UTF-16 validation and splitting happen once. It does not store Flow's full helper/client payload:

- `contents` duplicates the three substrings and is discarded after a validated split.
- `isEditable` does not affect formatting or whether Yazar attempts to paste.
- `accessibilityIsFunctioning` and `couldNotGetTextBoxInfo` collapse into presence or absence of this value.
- The focused element identity remains private session state in the capture object.

The bundle identifier stays in the value because capture already resolves it for the Notes correction and the roadmap's app-specific formatting will need the identity of the same stop-time target. This adds shape, not formatting capability; the generic fitter ignores it.

The initializer rejects negative, overflowing, or out-of-bounds ranges. It performs no lossy clamping.

### `TextContextCapture`

A main-actor session object that hides Accessibility representations, focus observation, traversal, and the Apple Notes correction. It owns no formatting policy.

```swift
@MainActor
final class TextContextCapture {
    /// Starts a new session, immediately replacing any prior snapshot with the
    /// focused target's current context and watching focus until `finish()`.
    func begin()

    /// Refreshes once at dictation stop, tears down observation, and returns the
    /// newest result. AX failure returns nil and never prevents delivery.
    func finish() -> TextInsertionContext?

    /// Tears down observation and discards context for an abandoned dictation.
    func cancel()
}
```

`begin()` is idempotent by first cancelling an unfinished session. `finish()` and `cancel()` leave the object ready for reuse. Neither method throws: unavailable context is an expected degradation state, not a dictation failure.

The capture session performs these operations behind that interface:

1. Identify the frontmost process, opt its application element into `AXManualAccessibility` and `AXEnhancedUserInterface`, then read `kAXFocusedUIElementAttribute` from the system-wide AX element. Chromium and Electron can otherwise withhold the useful focused node entirely. Reacquire the focused element after activation and resolve its owning process and bundle ID.
3. Recover contents through `AXValue`, a full `AXStartTextMarker`/`AXEndTextMarker` document range, or `AXNumberOfCharacters` plus parameterized `AXStringForRange`.
4. Recover selections through `AXSelectedTextRange`, `AXSharedCharacterRange`, every usable `AXSelectedTextRanges` entry, and `AXSelectedTextMarkerRange`. Decode ordinary ranges as `CFRange`. Preserve marker ranges until contents and selection nodes have been paired, then ask both nodes to translate the endpoints with `AXIndexForTextMarker`; web editors often expose the marker on a focused child but only let the web-area ancestor convert it. Feed every resulting UTF-16 range through the same validated `TextInsertionContext` constructor.
5. Traverse the focused subtree with both `AXVisibleChildren` and `AXChildren`, then follow only the focused element's ancestor chain. Keep the walk cycle-safe and bounded to 1,000 elements; do not fan back out through ancestors' unrelated siblings. Match Flow's role order: evaluate static text and text fields directly, evaluate childless text areas directly, and search a generic focused parent's descendants before falling back to that parent.
6. Reconcile contents and selection state exposed on different ancestor/descendant nodes. Keep conventional and marker coordinate spaces separate while trying every distinct representation an element exposes; an empty `AXValue` must not hide nonempty `AXStringForRange` contents. For direct text roles, prefer local value/range state before marker state because Electron can inherit document-wide markers onto a field-local `AXTextArea`. Only focused-subtree text, group, and web-area nodes may supply marker selections, preventing document markers inherited by checkboxes and ancestor containers from masquerading as textbox context. If any selected-text representation agrees with the range contents, accept it. Otherwise continue probing or use an exact selected-text occurrence only when it appears once, instead of returning known-wrong context.
7. Apply the Apple Notes correction inside capture, where the AX ambiguity belongs: for bundle ID `com.apple.notes`, an empty selection, nonempty `afterText`, and `beforeText` ending in `\n`, move that newline to the start of `afterText`.
8. Treat unsupported attributes, invalid types or ranges, traversal exhaustion, and permission loss as nil. Do not consult AX editability before returning context and do not block `Inserter`.

Focus tracking follows AX's real process boundary. The session observes `kAXFocusedUIElementChangedNotification` on the current application's AX root, and watches `NSWorkspace.didActivateApplicationNotification` to replace that per-process observer when the active app changes. Both events refresh the snapshot. The AX run-loop source runs on the main run loop, so its C callback re-enters the already-isolated object with `MainActor.assumeIsolated`; it does not introduce GCD. A target that does not support notifications still gets the mandatory start and stop captures.

### `TranscriptFitter`

A stateless pure module that owns the complete generic rule table and its Unicode classifications.

```swift
nonisolated enum TranscriptFitter {
    /// Fits an already-formatted transcript into the supplied textbox context.
    /// It mutates no state and returns the exact input only when it is empty.
    static func fit(
        _ transcript: String,
        to context: TextInsertionContext,
        startsWithProperNoun: Bool,
        properNouns: Set<String>
    ) -> String
}
```

The caller supplies a `Set<String>` because the specified check is exact membership. The formatter does not fetch profile, OCR, AX, personal, or team data itself.

The implementation keeps the shipped ordering in one function, with private classification predicates beside it rather than exposing a rule engine:

- Return a zero-length transcript unchanged; otherwise trim Unicode whitespace and newlines.
- Derive `lineBefore` after the final newline and `lineAfter` before the first newline, preserving empty lines and the untrimmed boundary strings.
- Refine a supplied proper-noun flag only for output with no literal ASCII space. Find the first contiguous Unicode-letter run and require exact set membership; an absent run also forces the flag off.
- Branch once on `selectedText.isEmpty`. A whitespace-only selection remains active.
- In the selection branch, apply S1 through S4 in order and return immediately.
- In the caret branch, apply C1 through C4 in order.
- Lowercase one leading extended grapheme only when the output contains more than one `Character`.
- Remove terminal `.`, `!`, and `?` with a suffix loop so the behavior does not depend on regex indexing.
- Classify letters and numbers from Unicode scalar general categories. Compare a `Character` with its lowercased form for the shipped caseless-letter behavior. Use a Unicode-script regex/property check for Han, Hiragana, and Katakana rather than maintaining incomplete scalar ranges.
- Encode boundary bridges, preceding/closing punctuation, operators, and East Asian terminal punctuation as private immutable sets whose contents match the handoff exactly.

No helper type represents individual rules. Removing `TranscriptFitter` would force the entire ordered ruleset into `Yazar`; its single call therefore pays for the module.

### `Yazar` integration

`Yazar` remains the only lifecycle coordinator and makes capture timing explicit:

```swift
private let textContextCapture = TextContextCapture()

// At a valid dictation press, before recorder startup:
textContextCapture.begin()

// At release, before transcription starts:
let insertionContext = textContextCapture.finish()
transcriptionTask = Task { [weak self] in
    // ...transcribe...
    self?.deliver(text, context: insertionContext)
}
```

The stop-time context travels as a local immutable value in the transcription task. `Yazar` does not keep a second synchronized snapshot property, and later focus changes during transcription cannot redirect formatting.

`cancel()`, `fail(_:)`, and `stop()` call `textContextCapture.cancel()` for every path that abandons a capture. The no-speech path finishes capture first so it removes observers, then discards the returned context.

Delivery chooses formatting only when context exists:

```swift
private func deliver(_ text: String, context: TextInsertionContext?) {
    let textToPaste = context.map {
        TranscriptFitter.fit(
            text,
            to: $0,
            startsWithProperNoun: false,
            properNouns: []
        )
    } ?? text

    switch Inserter.insert(textToPaste) {
        // Existing outcome handling stays unchanged.
    }
}
```

Yazar currently receives only a `String` from both transcribers and owns no proper-noun vocabulary, so the first implementation passes `false` and an empty set explicitly. That preserves the handoff's defined fallback rather than inventing a name detector. A later server post-processing response or vocabulary owner changes this one call; AX capture and fitting do not change.

`Inserter.insert(_:)` receives the final text and remains unchanged. In particular, nil context sends the original transcript—not a trimmed or partially adjusted value—to the clipboard and still attempts Command-V.

## Files

- Move `yazar/Dictation/Inserter.swift` to `yazar/Insertion/Inserter.swift` so all insertion behavior has one feature home; its contents and public behavior stay unchanged.
- Add `yazar/Insertion/TextInsertionContext.swift` for the canonical value and UTF-16-safe construction.
- Add `yazar/Insertion/TextContextCapture.swift` for AX reads, bounded traversal, focus observation, and Notes correction.
- Add `yazar/Insertion/TranscriptFitter.swift` for the pure ordered ruleset.
- Update `yazar/Dictation/Yazar.swift` only at capture lifecycle and delivery call sites.
- Add a filesystem-synchronized `yazarTests` group and Swift Testing target to `yazar.xcodeproj`, attach it to the shared `yazar` scheme's Test action, and preserve Main Actor/Swift 6.2-compatible build settings. The repository currently has no test target despite documenting one.
- Add `yazarTests/TextInsertionContextTests.swift` and `yazarTests/TranscriptFitterTests.swift`.
- Update `README.md` after verification to describe context-aware insertion and its unformatted fallback.

## Verification

### Automated behavior tests

Use Swift Testing and test observable results through `TranscriptFitter.fit`, not private helpers. Table-driven cases should cover:

- Every example in `isContinuingBefore`, `isContinuingAfter`, and `shouldAddLeadingSpace` by choosing contexts whose fitted output distinguishes true from false.
- Every S1-S4 and C1-C4 example, plus interactions that prove order: lowercase plus leading space, punctuation removal plus trailing space, and selection whitespace preservation after punctuation removal.
- Empty input versus whitespace-only input, one-character output, whitespace-only selection, multiple selected boundary spaces, tabs, non-breaking spaces, and empty current lines after newlines.
- Exact single-token proper-noun membership, case mismatch, multiword trust, punctuation before the first letter run, and a token containing only nonletters.
- Unicode letters and numbers, caseless letters, combining marks, emoji, Han/Hiragana/Katakana leading-space suppression, and every East Asian terminal punctuation mark.
- All boundary-bridge, closing/preceding punctuation, and operator characters, including the operator-at-start and operator-after-space cases.
- UTF-16 construction with BMP text, emoji/surrogate pairs before and inside a selection, combining sequences, a range at the end, and rejection of negative, overflowing, split-surrogate, and out-of-bounds ranges.

Run:

```text
xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug test
xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug build
xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug analyze
```

### Manual AX matrix

AX behavior needs real-process checks because a fake AX protocol would only test the fake. Verify:

- TextEdit text field/area: collapsed caret, active selection, start/end/middle insertion, and UTF-16 text around the caret.
- Apple Notes: caret immediately before and after a line break.
- Safari contenteditable and a conventional web input: marker and range representations.
- One Electron editor: nested parent/child selection exposure.
- Switching fields in one app and switching applications while holding the dictation trigger: the stop-time target wins.
- A control with inaccessible or unsupported text attributes: the exact transcript still reaches the clipboard and Yazar still posts Command-V.
- Accessibility permission revoked or AX notification registration rejected: dictation delivery continues without fitting.

## Next sibling

App-specific formatting adds one policy decision beside `TranscriptFitter` and selects it in `Yazar` using `context.applicationBundleIdentifier`; it does not modify AX traversal or `Inserter`. Proper-noun sources only populate the existing two formatter arguments.

## Not building

- No messaging period removal, Slack tags, Notion placeholders, signatures, snippets, or selective-formatting registry.
- No OCR, AX proper-noun extraction, user/team dictionary storage, or local proper-noun classifier.
- No change to `Transcriber`'s return shape before server post-processing exists.
- No direct AX text replacement or paste-success detection; clipboard plus Command-V remains the delivery boundary.
- No clipboard-copy fallback for reading selection and no persistent capture diagnostics payload.
- No protocol or dependency-injection seam around AX. There is one real implementation, and pure behavior remains testable without a mock.

## Needs your call

Nothing. The hard-to-reverse module boundary was compared above and the chosen shape leaves the roadmap's next features as local edits. Implementation can begin when explicitly requested.
