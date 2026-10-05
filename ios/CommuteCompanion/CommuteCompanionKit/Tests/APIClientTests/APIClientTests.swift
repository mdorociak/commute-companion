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
        #expect(error == .httpStatus(503, body: Data()))
    }
}

@Test
func getCarriesTheBodyOfANonSuccessfulResponse() async throws {
    let body = Data(#"{"code": "unknown_station"}"#.utf8)
    let transport = StubTransport { _ in
        HTTPResponse(data: body, statusCode: 404)
    }
    let client = APIClient(
        baseURL: try #require(URL(string: "https://example.com")),
        transport: transport
    )

    do {
        let _: Payload = try await client.get(path: "api/v1/stations", as: Payload.self)
        Issue.record("Expected an HTTP status error")
    } catch let error as APIError {
        #expect(error == .httpStatus(404, body: body))
    }
}

@Test(arguments: [
    URLError.Code.notConnectedToInternet,
    .networkConnectionLost,
    .dataNotAllowed,
    .internationalRoamingOff,
    .callIsActive,
    .cannotFindHost,
    .cannotConnectToHost,
    .dnsLookupFailed,
    .timedOut,
])
func getReportsAServerItCouldNotReachAsUnreachable(code: URLError.Code) async throws {
    let client = try makeClient { _ in throw URLError(code) }

    await #expect(throws: APIError.unreachable) {
        try await client.get(path: "api/v1/stations", as: Payload.self)
    }
}

@Test(arguments: [
    URLError.Code.secureConnectionFailed,
    .serverCertificateUntrusted,
    .appTransportSecurityRequiresSecureConnection,
])
func getPassesThroughAURLErrorThatIsNotAboutReachability(
    code: URLError.Code
) async throws {
    let client = try makeClient { _ in throw URLError(code) }

    let error = await #expect(throws: URLError.self) {
        try await client.get(path: "api/v1/stations", as: Payload.self)
    }
    #expect(error?.code == code)
}

@Test
func getReportsACancelledURLRequestAsCancellation() async throws {
    let client = try makeClient { _ in throw URLError(.cancelled) }

    await #expect(throws: CancellationError.self) {
        try await client.get(path: "api/v1/stations", as: Payload.self)
    }
}

@Test
func getPassesCancellationThrough() async throws {
    let client = try makeClient { _ in throw CancellationError() }

    await #expect(throws: CancellationError.self) {
        try await client.get(path: "api/v1/stations", as: Payload.self)
    }
}

@Test
func getPassesThroughATransportErrorItDoesNotRecognise() async throws {
    let client = try makeClient { _ in throw UnrecognisedTransportError() }

    await #expect(throws: UnrecognisedTransportError.self) {
        try await client.get(path: "api/v1/stations", as: Payload.self)
    }
}

@Test
func getReportsASuccessfulBodyOfTheWrongShapeAsDecoding() async throws {
    let client = try makeClient { _ in
        HTTPResponse(data: Data(#"{"unexpected": true}"#.utf8), statusCode: 200)
    }

    await #expect(throws: APIError.decoding) {
        try await client.get(path: "api/v1/stations", as: Payload.self)
    }
}

private struct UnrecognisedTransportError: Error {}

private func makeClient(
    responding handler: @escaping @Sendable (URLRequest) async throws -> HTTPResponse
) throws -> APIClient {
    APIClient(
        baseURL: try #require(URL(string: "https://example.com")),
        transport: StubTransport(responseHandler: handler)
    )
}
