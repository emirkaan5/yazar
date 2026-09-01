# Context-Aware Insertion Review Handoff

Status: working in the user's previously failing target. Native controls and real Safari
inputs/contenteditable editors also received direct verification. This document records the
debugging history and gives a second reviewer concrete claims to verify against the code.

## Review objective

Review the complete context-aware insertion feature, with most attention on
`yazar/Insertion/TextContextSearch.swift`. The formatter has deterministic unit coverage;
the difficult part is recovering one coherent textbox value and selection from inconsistent
macOS Accessibility representations without mistaking an entire browser document or an
unrelated control for the focused editor.

The intended degradation contract is non-negotiable:

```text
Context recovered:
    fit the transcript to the local text
    attempt Command-V

Context unavailable:
    leave the transcript unchanged
    still attempt Command-V
```

Accessibility editability and capture success do not decide whether Yazar attempts the
paste. `Inserter` remains responsible only for writing the clipboard and posting Command-V.

## Feature shape

The implementation separates these kinds of knowledge:

- `TextContextCapture` owns the stateful AX session: start/stop capture timing, focus
  observation, application activation, and the Apple Notes line-boundary correction.
- `TextContextSearch` owns one traversal: AX tree walking, incompatible text
  representations, and the pairing of contents with a selection.
- `AXElement` owns typed, failure-tolerant reads over the C Accessibility API and
  nothing about text boxes.
- `TextInsertionContext` is the canonical immutable formatting input. Its failable
  initializer splits complete AX contents with `NSString`/`NSRange`, preserving the
  UTF-16 coordinate system supplied by AX.
- `TranscriptFitter` owns the pure ordered S1-S4 and C1-C4 transformation rules.
- `Yazar` makes the lifecycle causal chain explicit: begin capture with dictation, finish
  it at recording stop, carry that immutable stop-time value through transcription, fit
  only when it exists, and pass the result to `Inserter`.

There is no AX protocol, general rule engine, registry, or second synchronized copy of the
captured context. The full design rationale lives in
`docs/plans/context-aware-insertion.md`.

## What failed first

### Attempt 1: conventional AX text attributes

The first capture path treated focused controls like native AppKit text fields. It read:

```text
AXValue
AXSelectedText
AXSelectedTextRange
AXSelectedTextRanges
```

This worked intermittently in conventional native controls. It failed in web and Electron
editors because the system-wide focused element often exposes only a generic container,
while the useful contents, range, or text-marker data lives on a descendant or ancestor.

Conclusion: ordinary AX ranges are necessary but cannot be the only representation.

### Attempt 2: add marker support and broad parent/child traversal

The next version added the web representation:

```text
AXSelectedTextMarkerRange
AXStartTextMarker
AXEndTextMarker
AXIndexForTextMarker
AXAttributedStringForTextMarkerRange
```

It also searched parents and children for a node that could provide the missing half of the
context. That increased apparent coverage, but it remained unreliable for two reasons:

1. It preferred marker-derived context when an element exposed both representations.
   Electron can inherit a document-wide marker range onto a field-local text area that also
   exposes the correct `AXValue` and ordinary selection range. The code therefore chose the
   larger but wrong representation.
2. Walking from a focused node to a parent and then back through all of that parent's
   children admitted unrelated siblings. Static labels, checkboxes, and generic web nodes
   can inherit page-level text markers even though they are not editable text controls.

Conclusion: more attributes and a wider traversal do not produce better context. The
capture must preserve representation boundaries, apply role-aware priority, and constrain
which nodes may contribute selection state.

### Rejected fallback: infer paste support from capture failure

The earlier paste-error work in `Inserter` had already shown that AX cannot reliably answer
whether an arbitrary focused target will accept Command-V. Context capture failure was
therefore never promoted into a paste eligibility signal. Clipboard-copy selection recovery
was also rejected as the ordinary capture path because it mutates shared clipboard state and
still cannot establish the complete before/selection/after context.

Conclusion: AX context recovery is best effort; paste delivery remains independent.

## How the failure was isolated

Temporary, redacted diagnostics were added to a signed Yazar build and removed after the
investigation. They recorded only roles, representation lengths, ranges, marker indexes,
and traversal relationships—not textbox contents.

### Trust diagnosis

Launching the executable directly from a shell reported `AXIsProcessTrusted() == false`.
That result was misleading because macOS Accessibility trust follows the signed application
identity and its LaunchServices launch context. Launching the built `.app` normally reported
`AXIsProcessTrusted() == true`.

This ruled out a missing user permission or a need to reset Accessibility authorization.

### Electron evidence

In T3 Code, the focused node was an `AXTextArea` exposing both:

- A field-local conventional value and ordinary collapsed range.
- An inherited marker representation whose contents covered 4,829 UTF-16 units of the
  Electron document.

The old ordering chose the 4,829-unit document marker before trying the local value/range.
That explained why native controls sometimes worked while Electron editors did not.

In Legcord, a focused checkbox/web-area path exposed document-wide marker attributes.
The broad traversal could combine those markers with text from unrelated sibling nodes,
confirming that successful AX calls did not imply a valid textbox context.

## Final capture strategy

The current implementation applies these constraints in order:

1. Confirm that the Yazar process has Accessibility trust.
2. Before requesting the system-wide focused element, set `AXManualAccessibility` and
   `AXEnhancedUserInterface` on the frontmost application. Chromium and Electron can keep
   their useful AX trees dormant until a trusted client opts in. Each process is opted in
   once per dictation session rather than on every refresh.
3. Read the focused element, resolve its actual process, opt that application in as well if
   it differs from the initial frontmost process, and refresh the focused element.
4. Walk the focused subtree through `AXVisibleChildren` and `AXChildren`. Separately follow
   the focused element's ancestor chain, but never fan back out through ancestor siblings.
   Track exact `AXUIElement` identity and stop after 1,000 elements.
5. Preserve conventional contents, marker contents, ordinary ranges, selected strings, and
   the marker range as distinct candidates. An empty `AXValue` must not erase a nonempty
   `AXStringForRange` candidate.
6. For direct text roles, try local conventional contents and ranges before text markers.
   This is the ordering that fixes Electron's field-local value versus inherited document
   marker conflict.
7. When a marker range is appropriate, ask both the contents node and selection node to
   translate its endpoints with `AXIndexForTextMarker`. Web editors often expose the marker
   on a child but only let an ancestor convert it into offsets.
8. Accept marker selections only from nodes inside the focused subtree whose role is direct
   text, group, or web area. Ancestor-inherited markers cannot independently masquerade as
   the focused textbox selection. This rule now gates the marker *reads*, so unrelated roles
   never reach the wire; marker contents may still come from a container above the focused
   element, because the web area holding the document text is often an ancestor.
9. Pair contents and selection candidates only on the same node or an ancestor/descendant
   relationship. Validate every resulting UTF-16 range through `TextInsertionContext`.
10. If selected text and range contents disagree, continue trying representations. As a
    last reconciliation, locate a nonempty selected string only when it occurs exactly once
    in the candidate contents; never guess among duplicate occurrences.
11. Apply the Apple Notes newline correction after recovering a coherent context.
12. Return `nil` for unsupported attributes, invalid coordinate spaces, missing permissions,
    or exhausted traversal. `Yazar` then sends the original transcript to `Inserter`.

## Capture timing

`TextContextCapture.begin()` refreshes at dictation start and begins observing:

- `kAXFocusedUIElementChangedNotification` in the active application.
- `NSWorkspace.didActivateApplicationNotification` when the user switches applications.

Each focus or application change replaces the latest snapshot. `finish()` performs one last
refresh at recording stop, tears down observers, and returns that newest context. `Yazar`
then captures it as a local immutable value in the transcription task, so focus changes
during the slower transcription phase cannot redirect formatting.

Cancellation and failure paths tear down capture. Notification registration failure does
not prevent the required start-time and stop-time refreshes.

## Real-application verification performed

A temporary local HTML fixture was opened in real Safari and exercised through the signed
Yazar application:

| Target | Fixture state | Recovered UTF-16 lengths |
| --- | --- | --- |
| Conventional `<input>` | `Hello| world`, caret offset 5 | before 5, selected 0, after 6 |
| `contenteditable` | `Hello| world`, caret offset 5 | before 5, selected 0, after 6 |
| `contenteditable` | selection offsets 2 through 7 | before 2, selected 5, after 4 |

The diagnostic build also reproduced the conflicting local-range/document-marker state in
T3 Code before the ordering fix. The temporary probe arguments, logging, fixture, and
profiling artifacts were removed from the final source.

Automated verification completed on the clean implementation:

```text
xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug test
xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug analyze
```

The test suite covers the formatter's rule ordering and Unicode boundaries plus
`TextInsertionContext` UTF-16 splitting and invalid-range rejection. AX traversal remains a
real-process concern; a mocked AX protocol would test an invented accessibility tree rather
than the incompatible trees that caused this bug.

## Known limits and unverified cases

- Secure text fields and controls that intentionally expose no text cannot provide fitting
  context. Yazar must still attempt the paste with the unchanged transcript.
- Canvas-based editors may expose neither useful ranges nor markers.
- Safari received controlled input, caret, and active-selection verification. T3 Code
  supplied direct pre-fix diagnostic evidence for the representation conflict, followed by
  successful user verification of the corrected build. Chromium, Brave, Firefox, and Apple
  Notes have not received the same controlled matrix in this debugging pass.
- The proper-noun flag and vocabulary have been removed from `TranscriptFitter`. They only
  ever arrived as `false` and an empty set, which made both guards unconditionally true.
  Yazar therefore lowercases single-token proper names in continuing sentences, exactly as
  it did while the arguments existed. Restoring the rule is one parameter, one branch, and
  one call site once a transcriber returns more than a string.

These limits should not lead the reviewer to couple context availability to paste delivery
or add clipboard mutation as a hidden fallback.

## Reviewer map

Read the feature as one unit of intent:

1. `docs/plans/context-aware-insertion.md` — intended architecture and exact rules.
2. `docs/plans/context-aware-insertion-simplification.md` — what later moved, and why.
3. `yazar/Insertion/TextContextSearch.swift` — the corrected traversal and representation
   ordering.
4. `yazar/Insertion/TextContextCapture.swift` — AX session timing and observation.
5. `yazar/Insertion/AXElement.swift` — typed reads over the C Accessibility API.
6. `yazar/Insertion/TextInsertionContext.swift` — canonical value and UTF-16 boundary.
7. `yazar/Insertion/TranscriptFitter.swift` — pure local rules.
8. `yazar/Dictation/Yazar.swift` — lifecycle integration and nil-context degradation.
9. `yazar/Insertion/Inserter.swift` — unchanged clipboard/Command-V delivery boundary.
10. `yazarTests/TextInsertionContextTests.swift` and
    `yazarTests/TranscriptFitterTests.swift` — behavior coverage.

The highest-value review questions are:

- Can any traversal path still combine contents and selection from unrelated nodes?
- Can an inherited document marker outrank a valid field-local ordinary range for a direct
  text role?
- Does marker-to-index conversion always use the same contents coordinate space passed to
  `TextInsertionContext`?
- Can an empty or stale AX representation hide a later valid candidate?
- Do focus changes, application changes, finish, cancellation, and failure each leave one
  clear latest-context owner and tear down observers exactly once?
- Does every capture failure preserve the original transcript and still reach
  `Inserter.insert`?
- Do `NSString` and `NSRange` remain the only consumers of AX offsets?
- Does the formatter preserve the exact rule order and avoid using document-wide text
  outside the current line?
- Does any proposed simplification accidentally merge conventional and marker coordinate
  spaces or broaden traversal back into unrelated siblings?

## Suggested manual review matrix

For each target, test a collapsed caret at the beginning, middle, and end; an active
selection; and text containing an emoji before the selection:

- TextEdit or another native AppKit text area.
- Safari `<input>`, `<textarea>`, and `contenteditable`.
- Chromium or Brave equivalents.
- One Electron editor, preferably T3 Code or another editor that exposes both local ranges
  and document markers.
- Apple Notes immediately before and after a newline.
- A non-text control in a web/Electron app to confirm context returns unavailable rather
  than borrowing text from a sibling.
- A target that denies text attributes to confirm Yazar still attempts Command-V with the
  original transcript.

When inspecting AX diagnostics, log roles, identities, range values, representation lengths,
and ancestry only. Do not log user textbox contents.
