# Yazar

<img width="500" alt="yazar_intro" src="https://github.com/user-attachments/assets/0593fad3-8aae-40b9-a3cf-3b86097bd94e" />


Yazar is a focused macOS app that does one thing: speech to text.

I built it because the options I found were heavy Electron apps, paid, or both. Yazar is lightweight, native, launches instantly, and disappears when you're done.

## Features

- Hold-to-record dictation from anywhere in macOS
- Configurable dictation key: any modifier, or a pair of them
- Automatic text insertion into the active app, with your clipboard restored afterwards
- On-device transcription with Apple Speech
- Configurable OpenRouter transcription models
- Selectable transcription language and provider
- Selectable audio input and status sound themes
- OpenRouter API keys stored in the macOS Keychain

## Requirements

- macOS 26.5 or later
- Xcode with the macOS 26.5 SDK or later
- An [OpenRouter](https://openrouter.ai/) API key if you use the OpenRouter provider

## Build from source

1. Clone the repository.
2. Open `yazar.xcodeproj` in Xcode.
3. Select the `yazar` scheme and run the app.
4. Choose Apple Speech or OpenRouter in Yazar Settings. Enter an OpenRouter API key if needed.
5. Grant Microphone and Accessibility access when prompted.
6. If you keep the default 🌐 Globe dictation key, open System Settings → Keyboard and set “Press 🌐 key to” to “Do Nothing.” Choosing any other key in Yazar Settings → Dictation skips this step.

## Usage

Yazar runs in the menu bar.

- Hold the dictation key to record. It is 🌐 Globe until you change it in Settings → Dictation, where you can pick any modifier or a pair such as ⌃⌥.
- Release it to transcribe and paste the text.
- Press Escape while recording or transcribing to cancel.
- Use the menu bar icon to change the dictation key, transcription provider, model, language, microphone, or sounds.

Yazar pastes by putting the text on the clipboard and pressing ⌘V, which is the only insertion path that works across native, web and Electron text fields. What you had copied goes back afterwards; turn that off in Settings → Dictation if you would rather keep the transcription on the clipboard.

Apple Speech processes recordings on your Mac. macOS may download the selected language asset into system storage the first time you use it and manages later model updates. Yazar does not write recordings to disk.

When you select OpenRouter, Yazar sends each recording directly to OpenRouter for transcription. Your API key stays in the macOS Keychain.

## Contributing

Bug reports and focused pull requests are welcome. For larger changes, open an issue first so the approach can be discussed before implementation.
