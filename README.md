# Yazar

<img width="500" alt="yazar_intro" src="https://github.com/user-attachments/assets/0593fad3-8aae-40b9-a3cf-3b86097bd94e" />


Yazar is a focused macOS app that does one thing well: speech to text.

I built it because the options I found were heavy Electron apps, paid, or both. Yazar is lightweight, native, launches instantly, and disappears when you're done.

## Features

- **Global hotkey:** hold to record from anywhere
- **Smart formatting:** context-aware capitalization, punctuation, and spacing 
- **Use any model:** 
	- Transcribe entirely on-device with **Apple Speech Transcription**.
	- Bring your own API key and use any transcription model through **OpenRouter**.
- **Per-keyboard routing:** optionally set different providers and models per input source
- **Per-app formatting rules:** Customize formatting for individual apps or create app groups that share the same rules.
- **Full control:** pick your transcription language, provider, audio input, and sound theme


## Usage

Yazar lives in the menu bar. There is nothing to set up. run it, grant Microphone and Accessibility access, and start dictating.

1. Hold the dictation key (🌐 Globe by default) and speak.
2. Release it. Yazar transcribes and pastes the text where you were typing.
3. Press Escape to cancel.

Everything else is in Settings: pick a different dictation key, provider, model, language, microphone, or sound theme.

A few details worth knowing:

- Yazar matches capitalization and spacing to the text around your caret. Every transcription also goes to the clipboard, so you can paste it yourself if an app blocks ⌘V.
- Apple Speech runs on your Mac. macOS downloads the language asset the first time you use it.
- OpenRouter sends each recording to OpenRouter. Your API key stays in the macOS Keychain.
- Yazar does not keep recordings on disk.

## Requirements

- macOS 26.5 or later
- An [OpenRouter](https://openrouter.ai/) API key if you use the OpenRouter provider

## Build from source

1. Clone the repository.
2. Open `yazar.xcodeproj` in Xcode.
3. Select the `yazar` scheme and run the app.
4. Choose Apple Speech or OpenRouter in Yazar Settings. Enter an OpenRouter API key under Settings → Providers if needed.
5. Grant Microphone and Accessibility access when prompted.
6. If you keep the default 🌐 Globe dictation key, open System Settings → Keyboard and set “Press 🌐 key to” to “Do Nothing.” Choosing any other key in Yazar Settings → Dictation skips this step.

## Contributing

Bug reports and focused pull requests are welcome. For larger changes, open an issue first so the approach can be discussed before implementation.
