import Foundation
import Testing
@testable import yazar

@Suite("Local LLM client", .serialized)
struct LocalLLMClientTests {
    private let baseURL = URL(string: "http://127.0.0.1:52999")!

    init() {
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    private func respond(status: Int, json: String) {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
    }

    @Test("Returns the assistant message content")
    func returnsContent() async throws {
        respond(status: 200, json: """
            {"choices":[{"message":{"content":"  Hello.  "},"finish_reason":"stop"}]}
            """)
        let client = LocalLLMClient(baseURL: baseURL, model: "mlx-community/Qwen3-4B-Instruct-2507-4bit")
        let reply = try await client.complete(system: "s", user: "u", expectsJSON: false)
        #expect(reply == "Hello.")
    }

    @Test("A non-2xx status surfaces the server's detail message")
    func serviceError() async {
        respond(status: 500, json: #"{"detail":"model failed to load"}"#)
        let client = LocalLLMClient(baseURL: baseURL, model: "m")
        await #expect(throws: LocalLLMClientError.self) {
            try await client.complete(system: "s", user: "u", expectsJSON: false)
        }
    }

    @Test("An empty choices array is an empty-reply error")
    func emptyChoices() async {
        respond(status: 200, json: #"{"choices":[]}"#)
        let client = LocalLLMClient(baseURL: baseURL, model: "m")
        await #expect(throws: LocalLLMClientError.self) {
            try await client.complete(system: "s", user: "u", expectsJSON: false)
        }
    }

    @Test("finish_reason length with no content is reported as truncated")
    func truncated() async {
        respond(status: 200, json: """
            {"choices":[{"message":{"content":""},"finish_reason":"length"}]}
            """)
        let client = LocalLLMClient(baseURL: baseURL, model: "m")
        await #expect(throws: LocalLLMClientError.self) {
            try await client.complete(system: "s", user: "u", expectsJSON: true)
        }
    }

    @Test("A blank model id is rejected before any request")
    func missingModel() async {
        let client = LocalLLMClient(baseURL: baseURL, model: "   ")
        await #expect(throws: LocalLLMClientError.self) {
            try await client.complete(system: "s", user: "u", expectsJSON: false)
        }
    }
}
