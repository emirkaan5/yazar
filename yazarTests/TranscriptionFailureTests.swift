import Foundation
import Testing
@testable import yazar

@Suite("Transcription failures")
struct TranscriptionFailureTests {
    @Test("Structured statuses drive recovery without interpreting server prose")
    func statuses() {
        #expect(TranscriptionFailure.httpStatus(401) == .credentials)
        #expect(TranscriptionFailure.httpStatus(402) == .paymentRequired)
        #expect(TranscriptionFailure.httpStatus(403) == .accessDenied)
        #expect(TranscriptionFailure.httpStatus(429) == .rateLimited)
        #expect(TranscriptionFailure.httpStatus(503) == .serviceUnavailable)
        #expect(TranscriptionFailure.httpStatus(413) == .http(413))
        #expect(TranscriptionFailure(URLError(.timedOut)) == .timedOut)
        #expect(TranscriptionFailure(URLError(.notConnectedToInternet)) == .network)
        #expect(TranscriptionFailure(NSError(domain: "private response body", code: 1)) == .unknown)
    }
}
