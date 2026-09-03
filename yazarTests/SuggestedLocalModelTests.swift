import Testing
@testable import yazar

@Suite("Suggested local models")
struct SuggestedLocalModelTests {
    @Test("The default id is one of the suggestions")
    func defaultIsSuggested() {
        #expect(SuggestedLocalModel.all.contains { $0.id == SuggestedLocalModel.defaultID })
    }

    @Test("Every id looks like a Hugging Face repo")
    func idsAreRepoShaped() {
        for model in SuggestedLocalModel.all {
            let parts = model.id.split(separator: "/")
            #expect(parts.count == 2)
            #expect(!model.summary.isEmpty)
        }
    }
}
