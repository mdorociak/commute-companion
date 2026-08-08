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
    func fetchStationsPropagatesTransportError() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))

        let apiClient = APIClient(
            baseURL: baseURL,
            transport: FailingHTTPTransport()
        )

        let repository = RemoteStationsRepository(
            apiClient: apiClient
        )

        await #expect(throws: TestError.transport) {
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

private struct FailingHTTPTransport: HTTPTransport {
    func response(for request: URLRequest) async throws -> HTTPResponse {
        throw TestError.transport
    }
}

private enum TestError: Error {
    case transport
}
