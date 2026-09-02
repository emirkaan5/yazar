# Overlay Timer Visibility

## What and why

Add a persisted Dictation setting that lets people hide the elapsed recording timer. Keep the preference in the existing `Settings` owner so the overlay reacts live without duplicating state in the recording engine.

## Shape

- `Settings` knows the persisted `showRecordingTimer` preference and defaults it to `true`, preserving current behavior for existing installs.
- `DictationSettingsView` exposes the preference as a switch beside the other recording feedback controls.
- `OverlayView` reads the same settings instance, conditionally creates the timer, and derives a narrower recording capsule when the timer is hidden.
- `OverlayPanel` and `AppDelegate` only pass the existing settings dependency to the overlay; they do not observe or copy the preference.

## Interface

The construction path becomes:

```swift
OverlayPanel(yazar: yazar, settings: settings)
OverlayView(yazar: yazar, settings: settings)
```

The setting binds directly at the UI call site:

```swift
Toggle("Show timer", isOn: $settings.showRecordingTimer)
```

`showRecordingTimer` persists through `UserDefaults`, has no error mode, and takes effect immediately. Hiding it removes only the elapsed label; the waveform and all non-recording overlay states remain unchanged.

## Next sibling

Another overlay display preference would add one key and property in `Settings`, one settings row, and one conditional at its overlay use site; it would not change `Yazar`.

## Not building

Do not add an overlay preferences type, environment key, or generalized component-visibility system. One direct boolean matches the current requirement and the existing settings model.

## Verification

- Build the Debug scheme with `xcodebuild`.
- Confirm a fresh defaults suite reads `showRecordingTimer` as `true` and persists both values if a focused `Settings` test can avoid unrelated Keychain state.
- Manually verify that changing the switch updates the active recording overlay, the timer remains hidden on the next launch, and both capsule widths stay centered.

## Needs your call

None. This change adds one reversible preference and follows existing module boundaries; implementation can begin.
