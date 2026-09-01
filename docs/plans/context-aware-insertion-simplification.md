# Context-Aware Insertion Simplification Plan

Status: applied September 1, 2026. Companion to `context-aware-insertion.md`
(design) and `context-aware-insertion-review-handoff.md` (debugging history).

The feature works. This plan reduces its size without weakening the AX behavior
that the handoff proved was necessary.

**What shipped differs from the proposal in four places. See "Outcome" at the
end before reading the steps as a description of the code.**

## Where the 729 lines actually are

`yazar/Insertion/TextContextCapture.swift`, measured by section:

| Lines | Section | Knowledge it holds |
| --- | --- | --- |
| 1–75 | constants, session state, `begin`/`finish`/`cancel`, notification entry points | capture lifecycle |
| 77–208 | `captureContext` traversal stack machine | walk order |
| 210–234 | `sharesAncestry` / `isAncestor` | re-derived tree structure |
| 236–335 | `conventionalContext`, `context`, `contextByFinding` | representation pairing |
| 337–353 | `correctingNotesBoundary` | one app quirk |
| 355–525 | `makeProbe` and the typed AX readers | which attributes mean what |
| 527–598 | `cfRange`, `stringAttribute` … `copiedParameterizedAttribute` | how to read any AX attribute safely |
| 600–625 | `enableAccessibilityTree`, pid helpers | Chromium/Electron opt-in |
| 627–681 | `observeApplication` / `stopObserving` | AX + workspace observation |
| 683–712 | `ElementProbe`, `TraversalStep` | traversal records |
| 714–729 | C observer callback | main-actor re-entry |

Two thirds of the file is not the hard part. Roughly 250 lines are generic AX
plumbing plus traversal bookkeeping that duplicates what the walk already knows.
The genuinely hard, hard-won part — representation ordering, marker/conventional
separation, role-gated marker selection — is about 100 lines and stays as it is.

## What must survive unchanged

Every step below is measured against these. A change that breaks one is wrong,
regardless of how many lines it removes.

1. Capture failure never blocks paste. `Inserter.insert` still runs with the
   original transcript.
2. Conventional and marker coordinate spaces never merge.
3. For direct text roles, local value/range beats inherited document markers.
4. Marker selections come only from focused-subtree text, group, or web-area
   nodes.
5. Traversal follows the focused subtree plus the ancestor chain, and never fans
   back out through an ancestor's other children.
6. An empty `AXValue` never hides a nonempty `AXStringForRange`.
7. Only `NSString`/`NSRange` consume AX offsets.
8. `TranscriptFitter` rule order is untouched.

## Step 1 — Move generic AX plumbing to its own file

Lines 527–598 plus `copiedElement`/`copiedElements` know nothing about text
boxes. They answer one question: how to get a typed Swift value out of an
`AXUIElement` without crashing on an unexpected CF type. That is a separate type
per `CLAUDE.md`, and separating it makes the remaining file readable.

Add `yazar/Insertion/AXElement.swift`:

```swift
/// Typed, failure-tolerant reads over the C Accessibility API. Every accessor
/// returns nil for a missing attribute or an unexpected CF type; callers treat
/// absence and wrong type the same way.
extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef?
    func parameterized(_ name: String, _ parameter: CFTypeRef) -> CFTypeRef?
    func element(_ name: String) -> AXUIElement?
    func elements(_ name: String) -> [AXUIElement]
    func string(_ name: String) -> String?          // String or NSAttributedString
    func number(_ name: String) -> Int?
    func range(_ name: String) -> NSRange?          // decodes AXValue .cfRange
    var processID: pid_t? { get }
}
```

Accessors take `String`, not `CFString`, and cast internally. That removes the 25
`as CFString` casts at the call sites and shortens every read:

```swift
// before
stringAttribute(kAXValueAttribute as CFString, from: element)
// after
element.string(kAXValueAttribute)
```

`elements(_:)` returns `[]` rather than `[AXUIElement]?`; no caller distinguishes
"no attribute" from "empty list", and both current call sites already write
`?? []`.

Pure move plus signature change. No behavior change, nothing to re-verify beyond
a build.

Expected: `TextContextCapture` loses about 100 lines; `AXElement.swift` is about
110.

## Step 2 — Make ancestry structural instead of re-derived

`isAncestor` (lines 219–234) rebuilds the tree from `AXParent` values by scanning
the `probes` array for a matching identity. The walk already knew every
parent/child link when it created the probe. This is a second source of truth for
the same fact, and it costs one AX round trip per element (`makeProbe` reads
`kAXParentAttribute`) plus an O(n) array scan inside an O(depth) loop inside the
O(n²) pairing loop.

Replace `ElementProbe.parentIdentity: AXUIElement?` with
`var parentIndex: Int?`, assigned by the walk:

```swift
private func isAncestor(_ ancestor: Int, of descendant: Int) -> Bool {
    var current = probes[descendant].parentIndex
    while let index = current {
        if index == ancestor { return true }
        current = probes[index].parentIndex
    }
    return false
}
```

The ancestor chain phase back-patches: after probing ancestor `A` of the
already-probed element at `index`, set `probes[index].parentIndex = A`. That is
the only mutation, and it states a fact the walk observed directly.

Removes: one AX call per element, the identity scan, and the `AXUIElement`
`Hashable` dependence in `isAncestor`'s `visited` set (the index chain cannot
cycle because indices only decrease along `parentIndex`… enforce with the
existing `visited` guard if you prefer, it is three lines).

Behavior identical: the same pairs qualify. Worth doing before Step 3 because it
makes the traversal rewrite mechanical.

## Step 3 — Replace the stack machine with recursion

`TraversalStep` (lines 707–712) is a hand-rolled DFS with a four-field `.visit`
payload and an `.evaluate(Int)` index, interleaved on one `pending` array. It
exists to express three ordering facts:

- direct text roles and childless text areas evaluate without descending,
- children evaluate before their parent,
- the ancestor chain evaluates after the whole focused subtree.

Recursion says that directly:

```swift
// Depth-first over the focused subtree. Returns the first context a node or one
// of its already-probed relatives can produce.
private func searchSubtree(_ element: AXUIElement, ...) -> TextInsertionContext?

// Focused element upward. Runs only when the subtree produced nothing.
private func searchAncestors(from element: AXUIElement, ...) -> TextInsertionContext?
```

`captureContext` becomes: trust check, tree opt-in, focused element,
`searchSubtree` else `searchAncestors`, then one `correctingNotesBoundary` call
at the single exit instead of the two return sites today.

AX trees are shallow enough for recursion; keep the existing 1,000-element budget
as the termination guarantee and add nothing else.

Removes: `TraversalStep`, the `pending` array, the `exploresChildren` /
`exploresParent` flags (implied by which function you are in), and the
`.evaluate` index indirection — about 60 lines.

Order to preserve exactly: children in `AXVisibleChildren + AXChildren` order,
each child fully searched before the parent evaluates, ancestors last.

## Step 4 — Probe markers only on nodes that can supply them

`makeProbe` issues roughly ten synchronous cross-process AX calls per element,
including three expensive ones (`AXStartTextMarker`, `AXEndTextMarker`,
`AXAttributedStringForTextMarkerRange`) plus `AXSelectedTextMarkerRange`. It does
this for every visited node before knowing whether the node can contribute.

`ElementProbe.supportsMarkerSelection` already names the only roles whose markers
are usable: direct text, `AXGroup`, `AXWebArea`, inside the focused subtree. Move
that test in front of the reads instead of after them:

```swift
let role = element.string(kAXRoleAttribute)
let probesMarkers = isInFocusedSubtree && (isDirectText(role)
    || role == Self.webAreaRole
    || role == kAXGroupRole)
```

`markerContents` still needs the same gate check — a marker range is only ever
paired with marker contents, and both sides are already constrained by the same
role rule.

This is the honest answer to "why does this touch 1,000 elements". It matters
because `captureContext` runs on the main actor inside `finishRecording()`, in
the latency path between the user releasing the trigger and transcription
starting, and again on every focus change during dictation. The slowest path
today is the failure path — a non-text focused control in an Electron app, where
the walk probes the whole subtree and every ancestor in full before returning
nil.

Removes little code. Cuts the dominant IPC cost. Re-run the Electron and web rows
of the manual matrix.

## Step 5 — Set `AXManualAccessibility` once per process, per session

`enableAccessibilityTree` runs on every `captureContext`, so at dictation start,
at every focus change, at every app switch, and at stop. It sets two attributes
and never unsets them.

Two changes:

- Track the pids opted in during the current session in a `Set<pid_t>` and skip
  repeats. `begin()`/`cancel()` clear it.
- Consider dropping `AXEnhancedUserInterface` and keeping only
  `AXManualAccessibility`. `AXManualAccessibility` is the Chromium/Electron
  opt-in the handoff's evidence actually needed. `AXEnhancedUserInterface` is the
  VoiceOver flag, and some AppKit apps change window layout when a client sets
  it. Setting it permanently on every app the user dictates into is a side effect
  Yazar does not need if `AXManualAccessibility` alone recovers the tree.

The second part is behavior-affecting: verify Chromium, Brave, and one Electron
editor with the flag removed before committing to it. If either target regresses,
keep both attributes and take only the once-per-session change.

## Step 6 — Delete the unreachable proper-noun parameters

`Yazar.swift:249–254` is the only call site and passes
`startsWithProperNoun: false, properNouns: []`. Inside `fit`, the flag starts
false and the refinement block can only set it to false again, so both
`!startsWithProperNoun` guards are unconditionally true. The parameters change
nothing today.

Delete both parameters, the refinement block (`TranscriptFitter.swift:27–32`),
`firstLetterRun` (lines 88–100), and the two guard clauses. Delete the
proper-noun test cases in `TranscriptFitterTests.swift`; keep every case that
also exercises another rule by re-expressing it without the argument.

Re-adding this later is one parameter, one branch, and one call site — exactly
the local edit the design brief promised when a transcriber starts returning more
than a string. Until then it is tested code that cannot run.

Removes about 35 lines from the fitter and about 70 from its tests.

This is the one step that deletes specified behavior. If you would rather keep
the vocabulary path staged for roadmap item 1 (LLM post-processing), skip this
step; nothing else in the plan depends on it.

## Step 7 — Small fitter fixes

- `belongsToUnspacedScript` compiles a `Regex` on every call inside a `try?`.
  Hoist it to `private static let unspacedScript = try? Regex(...)`. Same
  semantics, one compile per process. The design brief chose a script property
  over scalar ranges; that choice stands.
- `isLetter` and `isNumber` (lines 158–182) hand-roll general-category checks.
  Check whether `Character.isLetter` and `Character.isNumber` produce identical
  results across the existing Unicode test cases — they differ on multi-scalar
  characters, where the current code asks "any scalar is a letter". Delete the
  25 lines only if the suite passes unchanged; otherwise leave them with a
  comment saying why the standard property does not fit.
- Revert the trailing space added to `yazar/Dictation/DictationFailure.swift:24`.

## Deliberately not changing

- The representation priority rules and role gates. They are the feature.
- `contextByFinding`'s single-occurrence requirement.
- `correctingNotesBoundary`. Eighteen lines for one documented AX quirk, in the
  layer that owns AX quirks.
- The `TextInsertionContext` failable initializer and its UTF-16 boundary check.
- `Yazar`'s lifecycle wiring. `begin`/`finish`/`cancel` at four call sites, the
  context carried as a local immutable value into the transcription task.
- No AX protocol or mock. The handoff is right: a fake tree would test the fake.
- `ElementProbe` stays an eager record. It is the memo that keeps the O(n²)
  pairing loop from re-reading attributes, which is a reason that pays for the
  type.

## Expected result

| File | Now | After |
| --- | --- | --- |
| `TextContextCapture.swift` | 729 | ~370 |
| `AXElement.swift` | — | ~110 |
| `TranscriptFitter.swift` | 197 | ~160 |
| `TranscriptFitterTests.swift` | 322 | ~250 |

Feature total drops from about 990 lines to about 640, with the AX plumbing
readable on its own and the traversal reading as a depth-first search rather than
a stack machine.

`yazar.xcodeproj` uses filesystem-synchronized groups, so adding
`AXElement.swift` needs no project edit.

## Order and verification

Steps 1–3 are refactors with no intended behavior change. Take them together and
gate on:

```text
xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug test
xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug analyze
```

Steps 4 and 5 change what Yazar asks the target for. Each needs the handoff's
manual matrix, run from the signed `.app` and not from the shell:

- TextEdit: caret at start, middle, end; active selection.
- Safari `<input>`, `<textarea>`, `contenteditable`: caret and selection.
- Chromium or Brave: the same three.
- One Electron editor exposing both a local range and a document marker.
- Apple Notes immediately before and after a newline.
- A non-text control in an Electron app: context must come back unavailable, not
  borrowed from a sibling.
- A target that denies text attributes: the exact transcript still reaches the
  clipboard and Command-V still posts.

Steps 6 and 7 are covered by the unit suite alone.

Log roles, ranges, representation lengths, and ancestry during any diagnostic
pass. Never log textbox contents.

## Outcome

Applied. `xcodebuild test` and `xcodebuild analyze` both succeed, with no new
warnings. Four things went differently:

### The search became its own type

The plan kept one `TextContextCapture.swift` of about 370 lines. Splitting the
traversal out instead of threading `probes` and `bundleIdentifier` through every
recursive call gave two files that each answer one question:
`TextContextCapture` decides *when* to look and which snapshot survives;
`TextContextSearch` decides *how* to read a textbox and lives for exactly one
traversal. This also matches the repository's one-type-per-file rule.

Final shape:

| File | Lines |
| --- | --- |
| `TextContextCapture.swift` | 215 |
| `TextContextSearch.swift` | 364 |
| `AXElement.swift` | 138 |
| `TranscriptFitter.swift` | 175 |
| `TranscriptFitterTests.swift` | 233 |

The capture feature went from 990 lines to 890 across five files instead of
three. Total fell less than projected because the ancestry and traversal
rewrites bought fewer lines than estimated; what they bought was the removal of
one AX round trip per element, an O(n³) worst case in `isAncestor`, and a
four-field traversal enum.

### `supportsMarkerSelection` disappeared instead of moving

Step 4 proposed gating marker reads by role while keeping the check. Gating the
read makes the check redundant: `selectedMarkerRange` is now non-nil only when
the role rule already passed, so the rule is enforced once, where the cost is,
rather than read-then-filtered. Marker *contents* keep a looser gate — role only,
without the focused-subtree requirement — because the web area holding the
document text is usually an ancestor of the focused editor.

### `AXEnhancedUserInterface` stayed

Step 5 offered dropping it pending verification. The manual matrix has not been
run, so only the once-per-session change was taken. Both attributes are still
set; they are now set once per process per dictation instead of on every
refresh, focus change, and app switch.

### The `Character.isLetter` swap was rejected

Step 7 proposed deleting the hand-rolled category checks if the suite passed
with `Character.isLetter`/`isNumber`. The suite did pass — and the swap is still
wrong. A direct comparison found 1,059 single-scalar BMP characters where the
two disagree, because the standard properties use the Unicode Alphabetic
property rather than the general category: Indic vowel signs, circled letters,
and Nl numerals all become letters. The suite passing only proved it does not
cover them. The category checks stay, with a comment recording the measurement.

Compiling the script regex once was also rejected: `Regex` is not `Sendable`, so
a `static let` does not compile in a `nonisolated` enum. `belongsToUnspacedScript`
now uses a regex literal, which the compiler validates and which drops the
`try?` and its `guard`. It builds the regex per call, which happens once per
dictation.

### Still outstanding

Steps 4 and 5 changed what Yazar asks a target for. The manual matrix in
"Order and verification" above has not been run against this build. The specific
risk is a contents-bearing node whose role is neither direct text, group, nor
web area, and which used to supply marker contents; Chromium, Brave, and one
Electron editor are the rows that would catch it.
