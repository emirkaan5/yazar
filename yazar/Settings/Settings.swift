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
        static let dictationTrigger = "dictationTrigger"
        static let restoreClipboard = "restoreClipboard"
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

    /// Raw text-field contents. `optionalLanguage` is the canonical reading of
    /// it, and persistence goes through that too, so the rule for what counts as
    /// "no language" is written once. A nil value clears the key.
    var language: String {
        didSet { defaults.set(optionalLanguage, forKey: Key.language) }
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

    var dictationTrigger: DictationTrigger {
        didSet { defaults.set(dictationTrigger.rawValue, forKey: Key.dictationTrigger) }
    }

    var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: Key.restoreClipboard) }
    }

#if DEBUG
    var demoMode: Bool {
        didSet { defaults.set(demoMode, forKey: Key.demoMode) }
    }
#endif

    private(set) var apiKeys: [TranscriptionProvider: String] = [:]
    private(set) var apiKeyError: String?

    /// The credential for whichever provider is selected, so the settings screen
    /// can bind straight to it and follow along when the provider changes.
    var selectedAPIKey: String {
        get { apiKey(for: transcriptionProvider) }
        set { setAPIKey(newValue, for: transcriptionProvider) }
    }

    func apiKey(for provider: TranscriptionProvider) -> String {
        apiKeys[provider] ?? ""
    }

    private func setAPIKey(_ key: String, for provider: TranscriptionProvider) {
        guard apiKey(for: provider) != key else { return }
        apiKeys[provider] = key
        do {
            try Keychain.save(key, for: provider)
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }

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
        dictationTrigger = defaults.string(forKey: Key.dictationTrigger)
            .flatMap(DictationTrigger.init(rawValue:))
            ?? .default
        restoreClipboard = defaults.object(forKey: Key.restoreClipboard) == nil
            ? true
            : defaults.bool(forKey: Key.restoreClipboard)
#if DEBUG
        demoMode = defaults.bool(forKey: Key.demoMode)
#endif
        do {
            try Keychain.migrateLegacyKey()
            for provider in TranscriptionProvider.allCases where provider.needsAPIKey {
                apiKeys[provider] = try Keychain.load(for: provider)
            }
            apiKeyError = nil
        } catch {
            apiKeyError = error.localizedDescription
        }
    }
}

/// One Keychain item per provider that needs a credential.
///
/// Yazar first shipped a single slot — service "ai.yazar.openrouter", account
/// "api-key" — which could only ever hold one provider's key. migrateLegacyKey
/// moves that item into the per-provider layout and deletes it, so the old shape
/// is described in exactly one place and disappears after the first launch.
private enum Keychain {
    static let service = "ai.yazar.credentials"
    private static let legacyService = "ai.yazar.openrouter"
    private static let legacyAccount = "api-key"

    static func load(for provider: TranscriptionProvider) throws -> String {
        guard let data = try read(service: service, account: provider.rawValue) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ value: String, for provider: TranscriptionProvider) throws {
        if value.isEmpty {
            try delete(service: service, account: provider.rawValue)
        } else {
            try write(Data(value.utf8), service: service, account: provider.rawValue)
        }
    }

    static func migrateLegacyKey() throws {
        guard let legacy = try read(service: legacyService, account: legacyAccount) else { return }
        let account = TranscriptionProvider.openRouter.rawValue
        // A key already stored in the new layout wins; the old item is stale.
        if try read(service: service, account: account) == nil {
            try write(legacy, service: service, account: account)
        }
        try delete(service: legacyService, account: legacyAccount)
    }

    private static func identity(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(service: String, account: String) throws -> Data? {
        var query = identity(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return data
    }

    private static func write(_ data: Data, service: String, account: String) throws {
        let identity = identity(service: service, account: account)
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

    private static func delete(service: String, account: String) throws {
        let status = SecItemDelete(identity(service: service, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
    }
}
