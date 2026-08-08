import Foundation
import Testing
import APIClient
@testable import StationsFeature

@Suite
struct RemoteStationsRepositoryTests {

    @Test
    func fetchStationsWithSearchBuildsRequestAndMapsResponse() async throws {
        let json = """
        [
            {
                "id": "brzeg",
                "name": "Brzeg",
                "code": null
            }
        ]
        """

        let transport = HTTPTransportStub(
            response: HTTPResponse(
                data: Data(json.utf8),
                statusCode: 200
            )
        )

        let baseURL = try #require(URL(string: "https://example.com"))

        let apiClient = APIClient(
            baseURL: baseURL,
            transport: transport
        )

        let repository = RemoteStationsRepository(
            apiClient: apiClient
        )

        let stations = try await repository.fetchStations(search: "Brzeg")

        let capturedRequest = await transport.lastRequest
        let request = try #require(capturedRequest)
        let url = try #require(request.url)

        let components = try #require(
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        )

        #expect(components.path == "/api/v1/stations")
        #expect(
            components.queryItems?.contains(
                URLQueryItem(name: "search", value: "Brzeg")
            ) == true
        )

        #expect(
            stations == [
                Station(
                    id: "brzeg",
                    name: "Brzeg",
                    code: nil
                )
            ]
        )
    }

    @Test
    func fetchStationsWithoutSearchDoesNotAddQueryItems() async throws {
        let transport = HTTPTransportStub(
            response: HTTPResponse(
                data: Data("[]".utf8),
                statusCode: 200
            )
        )

        let baseURL = try #require(URL(string: "https://example.com"))

        let apiClient = APIClient(
            baseURL: baseURL,
            transport: transport
        )

        let repository = RemoteStationsRepository(
            apiClient: apiClient
        )

        _ = try await repository.fetchStations(search: nil)

        let capturedRequest = await transport.lastRequest
        let request = try #require(capturedRequest)
        let url = try #require(request.url)

        let components = try #require(
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        )

        #expect(components.path == "/api/v1/stations")
        #expect(components.queryItems == nil)
    }

    @Test
    func fetchStationsMapsOfflineErrorToUnavailable() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))

        let apiClient = APIClient(
            baseURL: baseURL,
            transport: OfflineHTTPTransport()
        )

        let repository = RemoteStationsRepository(
            apiClient: apiClient
        )

        await #expect(throws: StationsRepositoryError.unavailable) {
            try await repository.fetchStations(search: nil)
        }
    }

    @Test
    func fetchStationsMapsMalformedResponseToInvalidData() async throws {
        let transport = HTTPTransportStub(
            response: HTTPResponse(
                data: Data("not-json".utf8),
                statusCode: 200
            )
        )

        let baseURL = try #require(URL(string: "https://example.com"))

        let apiClient = APIClient(
            baseURL: baseURL,
            transport: transport
        )

        let repository = RemoteStationsRepository(
            apiClient: apiClient
        )

        await #expect(throws: StationsRepositoryError.invalidData) {
            try await repository.fetchStations(search: nil)
        }
    }

    @Test
    func fetchStationsMapsUnknownErrorToUnexpected() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))

        let apiClient = APIClient(
            baseURL: baseURL,
            transport: UnknownFailureHTTPTransport()
        )

        let repository = RemoteStationsRepository(
            apiClient: apiClient
        )

        await #expect(throws: StationsRepositoryError.unexpected) {
            try await repository.fetchStations(search: nil)
        }
    }

    @Test
    func fetchStationsPropagatesCancellation() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))

        let apiClient = APIClient(
            baseURL: baseURL,
            transport: CancellingHTTPTransport()
        )

        let repository = RemoteStationsRepository(
            apiClient: apiClient
        )

        await #expect(throws: CancellationError.self) {
            try await repository.fetchStations(search: nil)
        }
    }
}

private actor HTTPTransportStub: HTTPTransport {
    private let stubbedResponse: HTTPResponse

    private(set) var lastRequest: URLRequest?

    init(response: HTTPResponse) {
        self.stubbedResponse = response
    }

    func response(for request: URLRequest) async throws -> HTTPResponse {
        lastRequest = request
        return stubbedResponse
    }
}

private struct OfflineHTTPTransport: HTTPTransport {
    func response(for request: URLRequest) async throws -> HTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}

private struct UnknownFailureHTTPTransport: HTTPTransport {
    func response(for request: URLRequest) async throws -> HTTPResponse {
        throw TestError.transport
    }
}

private struct CancellingHTTPTransport: HTTPTransport {
    func response(for request: URLRequest) async throws -> HTTPResponse {
        throw CancellationError()
    }
}

private enum TestError: Error, Sendable {
    case transport
}
