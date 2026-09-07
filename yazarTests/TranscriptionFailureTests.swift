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

    /// The OpenRouter wire boundary. A 2xx status is not proof of success: work
    /// that fails after the response starts returns 200 with an error envelope,
    /// so the body decides and the status only classifies non-2xx replies.
    @Test("OpenRouter bodies classify into stable causes", arguments: [
        (200, #"{"text":"  Hello there.  "}"#, .success("Hello there.")),
        (200, #"{"text":""}"#, .success("")),
        (200, #"{"error":{"code":401,"message":"private words the user dictated","metadata":{"error_type":"authentication"}}}"#,
         .failure(.credentials)),
        (200, #"{"error":{"code":200,"metadata":{"error_type":"timeout"}}}"#, .failure(.timedOut)),
        (200, #"{"error":{"code":200,"metadata":{"error_type":"provider_overloaded"}}}"#,
         .failure(.serviceUnavailable)),
        (200, #"{"error":{"code":402,"message":"private billing prose"}}"#, .failure(.paymentRequired)),
        (200, #"{"error":{"code":413,"metadata":{"error_type":"payload_too_large"}}}"#, .failure(.http(413))),
        (200, #"{"choices":[]}"#, .failure(.invalidResponse)),
        (200, "<html>gateway</html>", .failure(.invalidResponse)),
        (429, #"{"error":{"code":429,"metadata":{"error_type":"rate_limit_exceeded"}}}"#, .failure(.rateLimited)),
        (500, "<html>gateway</html>", .failure(.serviceUnavailable)),
    ] as [(status: Int, body: String, expected: Result<String, TranscriptionFailure>)])
    func openRouterBodies(_ testCase: (status: Int, body: String, expected: Result<String, TranscriptionFailure>)) {
        let outcome = Result {
            try OpenRouterTranscriber.decodeResponse(Data(testCase.body.utf8), statusCode: testCase.status)
        }.mapError(TranscriptionFailure.init)
        #expect(outcome == testCase.expected)
        // Remote prose can quote what was dictated, so none of it may survive.
        if case .failure(let failure) = outcome {
            #expect(!failure.localizedDescription.contains("private"))
        }
    }
}
