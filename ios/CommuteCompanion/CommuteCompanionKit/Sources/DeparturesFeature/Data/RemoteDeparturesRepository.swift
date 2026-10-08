import Foundation
import APIClient

struct RemoteDeparturesRepository: DeparturesRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchDepartures(query: DepartureQuery) async throws -> [Departure] {
        do {
            let dtos = try await apiClient.get(
                path: "api/v1/stations/\(query.stationID)/departures",
                queryItems: Self.queryItems(for: query),
                as: [DepartureDTO].self
            )

            try Task.checkCancellation()

            return dtos.map { $0.toDomain() }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIError {
            throw Self.failure(for: error)
        } catch {
            throw DeparturesRepositoryError.unexpected
        }
    }

    private static func failure(for error: APIError) -> DeparturesRepositoryError {
        switch error {
        case .unreachable:
            .unreachable

        case .httpStatus(404, let body):
            failure(forNotFound: body)

        case .httpStatus(500..<600, _):
            .serverFailure

        case .httpStatus:
            .unexpected

        case .invalidResponse, .decoding:
            .invalidData

        case .invalidURL:
            .unexpected
        }
    }

    private static func queryItems(for query: DepartureQuery) -> [URLQueryItem] {
        guard let towards = query.towardsStationID else { return [] }

        return [URLQueryItem(name: "towards", value: towards)]
    }

    private static func failure(
        forNotFound body: Data
    ) -> DeparturesRepositoryError {
        guard
            let dto = try? JSONDecoder().decode(
                DepartureRequestErrorDTO.self,
                from: body
            ),
            let role = dto.unknownStationRole
        else {
            return .unexpected
        }

        return .unknownStation(role)
    }
}
