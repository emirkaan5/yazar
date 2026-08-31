import Foundation
import Observation
import Security

@MainActor
@Observable
final class Settings {
    private enum Key {
        static let transcriptionProvider = "transcriptionProvider"
        static let model = "model"
        static let language = "language"
        static let playSounds = "playSounds"
        static let soundTheme = "soundTheme"
        static let audioInputID = "audioInputID"
#if DEBUG
        static let demoMode = "demoMode"
#endif
    }

    private let defaults: UserDefaults

    var transcriptionProvider: TranscriptionProvider {
        didSet {
            defaults.set(transcriptionProvider.rawValue, forKey: Key.transcriptionProvider)
        }
    }

    var openRouterModel: String {
        didSet { defaults.set(openRouterModel, forKey: Key.model) }
    }

    var language: String {
        didSet {
            let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                defaults.removeObject(forKey: Key.language)
            } else {
                defaults.set(trimmed, forKey: Key.language)
            }
        }
    }

    var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Key.playSounds) }
    }

    var soundTheme: SoundTheme {
        didSet { defaults.set(soundTheme.rawValue, forKey: Key.soundTheme) }
    }

    var audioInputID: String {
        didSet { defaults.set(audioInputID, forKey: Key.audioInputID) }
    }

#if DEBUG
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Key.demoMode) }
    }
#endif

    var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            do {
                try Keychain.save(apiKey)
                apiKeyError = nil
            } catch {
                apiKeyError = error.localizedDescription
            }
        }
    }

    private(set) var apiKeyError: String?

    var optionalLanguage: String? {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transcriptionProvider = defaults.string(forKey: Key.transcriptionProvider)
            .flatMap(TranscriptionProvider.init(rawValue:))
            ?? .openRouter
        openRouterModel = defaults.string(forKey: Key.model) ?? "openai/whisper-1"
        language = defaults.string(forKey: Key.language) ?? ""
        playSounds = defaults.object(forKey: Key.playSounds) == nil
            ? true
            : defaults.bool(forKey: Key.playSounds)
        soundTheme = defaults.string(forKey: Key.soundTheme)
            .flatMap(SoundTheme.init(rawValue:))
            ?? .minimal
        audioInputID = defaults.string(forKey: Key.audioInputID)
            ?? AudioInput.defaultID
            ?? ""
#if DEBUG
        demoMode = defaults.bool(forKey: Key.demoMode)
#endif
        do {
            apiKey = try Keychain.load()
            apiKeyError = nil
        } catch {
            apiKey = ""
            apiKeyError = error.localizedDescription
        }
    }
}

private enum Keychain {
    static let service = "ai.yazar.openrouter"
    static let account = "api-key"

    static func load() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ value: String) throws {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if value.isEmpty {
            let status = SecItemDelete(identity as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError(status: status)
            }
            return
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            identity as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError(status: updateStatus)
        }

        var item = identity
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError(status: addStatus)
        }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
