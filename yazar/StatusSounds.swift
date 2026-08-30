import AppKit
import Foundation

enum StatusSound: String, Sendable {
    case start
    case stop
    case cancel
    case error
}

enum SoundTheme: String, CaseIterable, Identifiable, Sendable {
    case minimal
    case playful

    var id: Self { self }

    var displayName: String {
        switch self {
        case .minimal: "Minimal"
        case .playful: "Playful"
        }
    }
}

/// Resolves status sounds from a theme directory and plays them without blocking the main thread.
final class StatusSoundPlayer: @unchecked Sendable {
    private let bundle: Bundle
    private let queue = DispatchQueue(label: "yazar.sounds", qos: .userInitiated)
    private var sounds: [String: NSSound] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func play(_ status: StatusSound, theme: SoundTheme, enabled: Bool) {
        guard enabled else { return }

        queue.async { [self] in
            let key = "\(theme.rawValue)/\(status.rawValue)"
            let sound: NSSound
            if let cached = sounds[key] {
                sound = cached
            } else {
                guard let url = bundle.url(
                    forResource: status.rawValue,
                    withExtension: "wav",
                    subdirectory: "SFX/\(theme.rawValue)"
                ), let loaded = NSSound(contentsOf: url, byReference: true) else {
                    NSLog(
                        "Yazar could not load SFX/%@/%@.wav",
                        theme.rawValue,
                        status.rawValue
                    )
                    return
                }
                sounds[key] = loaded
                sound = loaded
            }

            sound.stop()
            sound.play()
        }
    }
}
