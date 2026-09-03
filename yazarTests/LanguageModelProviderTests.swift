import Foundation
import Testing
@testable import yazar

@MainActor
@Suite("Language model provider")
struct LanguageModelProviderTests {
    @Test("Only OpenRouter needs a credential")
    func credentials() {
        #expect(LanguageModelProvider.openRouter.needsAPIKey)
        #expect(!LanguageModelProvider.local.needsAPIKey)
    }

    @Test("Raw values round-trip for persistence")
    func rawValues() {
        for provider in LanguageModelProvider.allCases {
            #expect(LanguageModelProvider(rawValue: provider.rawValue) == provider)
        }
    }

    @Test("OpenRouter builds an OpenRouter client from the notes model")
    func openRouterClient() async throws {
        let settings = Settings(defaults: Self.emptyDefaults())
        settings.openRouterNotesModel = "some/notes-model"
        let engine = LocalLLMEngine(paths: LocalLLMPaths(root: Self.tempRoot()))

        let client = try await LanguageModelProvider.openRouter.makeClient(settings: settings, engine: engine)
        #expect(client is OpenRouterClient)
    }

    @Test("Local fails fast when the engine is not installed")
    func localWithoutEngine() async {
        let settings = Settings(defaults: Self.emptyDefaults())
        let engine = LocalLLMEngine(paths: LocalLLMPaths(root: Self.tempRoot()))

        await #expect(throws: LocalLLMError.self) {
            _ = try await LanguageModelProvider.local.makeClient(settings: settings, engine: engine)
        }
    }

    private static func emptyDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "LanguageModelProviderTests-\(UUID().uuidString)")!
        return defaults
    }

    private static func tempRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "llm-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
