# Repository Guidelines

## Project Structure & Module Organization

Yazar is a native macOS menu-bar app. Swift source lives in `yazar/`; `yazarApp.swift` and `Yazar.swift` coordinate the app, while focused files such as `Recorder.swift`, `Transcriber.swift`, and `Inserter.swift` own one part of the dictation flow. SwiftUI and AppKit presentation code lives beside them in `*View.swift` and `OverlayPanel.swift`.

Assets belong in `yazar/Assets.xcassets`, status sounds in `yazar/Resources/SFX`, and signing capabilities in `yazar/yazar.entitlements`. Keep project settings and target membership in `yazar.xcodeproj`. Maintenance utilities live in `scripts/` and `tools/`; release automation lives in `.github/workflows/`.

## Build, Test, and Development Commands

- `open yazar.xcodeproj` opens the project; select the shared `yazar` scheme and run it from Xcode.
- `xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug build` performs a local debug build.
- `xcodebuild -project yazar.xcodeproj -scheme yazar -configuration Debug analyze` runs Xcode's static analyzer.
- `scripts/make-appicon.sh path/to/icon-1024.png` regenerates every macOS app-icon size from one source PNG.

The app requires macOS 26.5 and its SDK. Runtime verification also requires Microphone and Accessibility permission plus an OpenRouter API key stored through the app.

## Coding Style & Naming Conventions

Follow the existing Swift style: four-space indentation, one primary type per file, `UpperCamelCase` types, and `lowerCamelCase` members. Name files after their main type. Prefer small domain types and direct calls; keep shared state in one owner and derive display values at use sites. Use Swift concurrency and actor isolation explicitly when work crosses threads. No formatter or linter is configured, so match surrounding code and treat compiler warnings as defects.

## Testing Guidelines

The project currently has no test target. Before submitting, run a Debug build and analyzer, then manually verify hold-to-record, Escape cancellation, transcription, text insertion, settings persistence, permission onboarding, and error states affected by the change. If you add a test target, place tests under `yazarTests/`, name files `TypeNameTests.swift`, and test behavior rather than implementation details.

## Commit & Pull Request Guidelines

Recent commits use short imperative summaries, for example `Capture Escape to cancel active dictation`. Keep each commit focused. Pull requests should explain the user-visible outcome, list verification performed, link relevant issues, and include screenshots or a short recording for UI changes. Discuss broad features in an issue before implementation. Never commit API keys, signing certificates, or generated `build/` output.
