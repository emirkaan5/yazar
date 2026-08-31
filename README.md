# Yazar

<img width="400" alt="yazar" src="https://github.com/user-attachments/assets/d75fcd7c-4c5e-4c80-9d8a-66f117e3bdcb" />


Yazar is a small macOS app that does one thing well: speech to text.

I built it because every option I found was either a heavy Electron app that didn't feel snappy, paid, or both. Yazar is native, lightweight, and gets out of your way.

## Features

- Hold-to-record dictation from anywhere in macOS
- Automatic text insertion into the active app
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
6. In System Settings → Keyboard, set “Press 🌐 key to” to “Do Nothing,” then relaunch Yazar.

## Usage

Yazar runs in the menu bar.

- Hold Fn/Globe to record.
- Release it to transcribe and paste the text.
- Press Escape while recording or transcribing to cancel.
- Use the menu bar icon to change the transcription provider, model, language, microphone, or sounds.

Apple Speech processes recordings on your Mac. macOS may download the selected language asset into system storage the first time you use it and manages later model updates. Yazar does not write recordings to disk.

When you select OpenRouter, Yazar sends each recording directly to OpenRouter for transcription. Your API key stays in the macOS Keychain.

## Contributing

Bug reports and focused pull requests are welcome. For larger changes, open an issue first so the approach can be discussed before implementation.
