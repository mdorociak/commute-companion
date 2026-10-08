import Foundation
import Testing
import APIClient
@testable import DeparturesFeature

@Suite
struct RemoteDeparturesRepositoryTests {

    @Test
    func fetchDeparturesBuildsStationPathAndMapsResponse() async throws {
        let json = """
        [
            {
                "id": "dep_f8a9c26b8a9d5f00bb6386d420915e62",
                "line": "D7",
                "destination": "Sędzisław",
                "departure_time": "2026-05-20T05:36:00+02:00",
                "platform": "II"
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
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        let departures = try await repository.fetchDepartures(
            query: DepartureQuery(stationID: "2246799")
        )

        let capturedRequest = await transport.lastRequest
        let request = try #require(capturedRequest)
        let url = try #require(request.url)

        #expect(url.path == "/api/v1/stations/2246799/departures")
        #expect(departures == [
            Departure(
                id: "dep_f8a9c26b8a9d5f00bb6386d420915e62",
                line: "D7",
                destination: "Sędzisław",
                scheduledAt: Date(timeIntervalSince1970: 1_779_248_160),
                platform: "II"
            )
        ])
    }

    @Test
    func fetchDeparturesSendsTheOnwardStationWhenThereIsOne() async throws {
        let transport = HTTPTransportStub(
            response: HTTPResponse(data: Data("[]".utf8), statusCode: 200)
        )
        let baseURL = try #require(URL(string: "https://example.com"))
        let repository = RemoteDeparturesRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport)
        )

        _ = try await repository.fetchDepartures(
            query: DepartureQuery(
                stationID: "2246799",
                towardsStationID: "wroclaw"
            )
        )

        let capturedRequest = await transport.lastRequest
        let request = try #require(capturedRequest)
        let url = try #require(request.url)
        let components = try #require(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        #expect(url.path == "/api/v1/stations/2246799/departures")
        #expect(components.queryItems == [
            URLQueryItem(name: "towards", value: "wroclaw")
        ])
    }

    @Test
    func fetchDeparturesOmitsTowardsWhenThereIsNoOnwardStation() async throws {
        let transport = HTTPTransportStub(
            response: HTTPResponse(data: Data("[]".utf8), statusCode: 200)
        )
        let baseURL = try #require(URL(string: "https://example.com"))
        let repository = RemoteDeparturesRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport)
        )

        _ = try await repository.fetchDepartures(
            query: DepartureQuery(stationID: "2246799")
        )

        let capturedRequest = await transport.lastRequest
        let request = try #require(capturedRequest)
        let url = try #require(request.url)

        #expect(url.query == nil)
    }

    @Test
    func fetchDeparturesReturnsEmptyArrayForEmptyResponse() async throws {
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
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        let departures = try await repository.fetchDepartures(
            query: DepartureQuery(stationID: "2246799")
        )

        #expect(departures.isEmpty)
    }

    @Test
    func fetchDeparturesMapsMalformedResponseToInvalidData() async throws {
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
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        await #expect(throws: DeparturesRepositoryError.invalidData) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesMapsOfflineErrorToUnreachable() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let apiClient = APIClient(
            baseURL: baseURL,
            transport: OfflineHTTPTransport()
        )
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        await #expect(throws: DeparturesRepositoryError.unreachable) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test(arguments: [500, 503])
    func fetchDeparturesMapsAServerErrorResponseToServerFailure(
        statusCode: Int
    ) async throws {
        let repository = try makeRepository(statusCode: statusCode, body: "")

        await #expect(throws: DeparturesRepositoryError.serverFailure) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesMapsANonHTTPResponseToInvalidData() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let apiClient = APIClient(
            baseURL: baseURL,
            transport: NonHTTPResponseTransport()
        )
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        await #expect(throws: DeparturesRepositoryError.invalidData) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesMapsAnUnknownOriginToUnknownStation() async throws {
        let repository = try makeRepository(
            statusCode: 404,
            body: #"{"code": "unknown_station", "reference": "station_id"}"#
        )

        await #expect(throws: DeparturesRepositoryError.unknownStation(.origin)) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesMapsAnUnknownOnwardStationToUnknownStation() async throws {
        let repository = try makeRepository(
            statusCode: 404,
            body: #"{"code": "unknown_station", "reference": "towards"}"#
        )

        await #expect(throws: DeparturesRepositoryError.unknownStation(.onward)) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesTreatsAnUnidentifiedNotFoundAsUnexpected() async throws {
        let repository = try makeRepository(
            statusCode: 404,
            body: "<html>Not Found</html>"
        )

        await #expect(throws: DeparturesRepositoryError.unexpected) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesMapsAContradictoryRequestToUnexpected() async throws {
        let repository = try makeRepository(
            statusCode: 400,
            body: #"{"code": "same_origin_and_destination", "reference": "towards"}"#
        )

        await #expect(throws: DeparturesRepositoryError.unexpected) {
            try await repository.fetchDepartures(
                query: DepartureQuery(stationID: "2246799", towardsStationID: "2246799")
            )
        }
    }

    @Test
    func fetchDeparturesMapsUnknownErrorToUnexpected() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let apiClient = APIClient(
            baseURL: baseURL,
            transport: UnknownFailureHTTPTransport()
        )
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        await #expect(throws: DeparturesRepositoryError.unexpected) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesPropagatesCancellation() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let apiClient = APIClient(
            baseURL: baseURL,
            transport: CancellingHTTPTransport()
        )
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        await #expect(throws: CancellationError.self) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }

    @Test
    func fetchDeparturesMapsCancelledURLErrorToCancellation() async throws {
        let baseURL = try #require(URL(string: "https://example.com"))
        let apiClient = APIClient(
            baseURL: baseURL,
            transport: CancelledURLHTTPTransport()
        )
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        await #expect(throws: CancellationError.self) {
            try await repository.fetchDepartures(query: DepartureQuery(stationID: "2246799"))
        }
    }
}

private func makeRepository(
    statusCode: Int,
    body: String
) throws -> RemoteDeparturesRepository {
    let transport = HTTPTransportStub(
        response: HTTPResponse(data: Data(body.utf8), statusCode: statusCode)
    )
    let baseURL = try #require(URL(string: "https://example.com"))

    return RemoteDeparturesRepository(
        apiClient: APIClient(baseURL: baseURL, transport: transport)
    )
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

private struct NonHTTPResponseTransport: HTTPTransport {
    func response(for request: URLRequest) async throws -> HTTPResponse {
        throw APIError.invalidResponse
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

private struct CancelledURLHTTPTransport: HTTPTransport {
    func response(for request: URLRequest) async throws -> HTTPResponse {
        throw URLError(.cancelled)
    }
}

private enum TestError: Error, Sendable {
    case transport
}
