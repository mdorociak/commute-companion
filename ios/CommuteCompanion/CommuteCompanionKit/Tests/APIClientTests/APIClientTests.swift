import Foundation
import Testing
@testable import APIClient

private struct Payload: Decodable, Equatable, Sendable {
    let value: String
}

private struct StubTransport: HTTPTransport {
    let responseHandler: @Sendable (URLRequest) async throws -> HTTPResponse

    func response(for request: URLRequest) async throws -> HTTPResponse {
        try await responseHandler(request)
    }
}

private actor RequestRecorder {
    private(set) var request: URLRequest?

    func record(_ request: URLRequest) {
        self.request = request
    }
}

@Test
func getBuildsRequestAndDecodesSuccessfulResponse() async throws {
    let recorder = RequestRecorder()
    let transport = StubTransport { request in
        await recorder.record(request)
        return HTTPResponse(
            data: Data(#"{"value":"ok"}"#.utf8),
            statusCode: 200
        )
    }
    let client = APIClient(
        baseURL: try #require(URL(string: "https://example.com/base")),
        transport: transport
    )

    let payload = try await client.get(
        path: "/api/v1/stations",
        queryItems: [URLQueryItem(name: "search", value: "Brzeg Dolny")],
        as: Payload.self
    )

    #expect(payload == Payload(value: "ok"))
    let request = await recorder.request
    #expect(request?.httpMethod == "GET")
    #expect(request?.url?.path == "/base/api/v1/stations")
    #expect(request?.url?.query == "search=Brzeg%20Dolny")
}

@Test
func getRejectsNonSuccessfulStatusCode() async throws {
    let transport = StubTransport { _ in
        HTTPResponse(data: Data(), statusCode: 503)
    }
    let client = APIClient(
        baseURL: try #require(URL(string: "https://example.com")),
        transport: transport
    )

    do {
        let _: Payload = try await client.get(path: "api/v1/stations", as: Payload.self)
        Issue.record("Expected an HTTP status error")
    } catch let error as APIError {
        #expect(error == .httpStatus(503))
    }
}
