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
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }

            throw DeparturesRepositoryError.unavailable
        } catch is DecodingError {
            throw DeparturesRepositoryError.invalidData
        } catch let error as APIError {
            switch error {
            case .invalidResponse:
                throw DeparturesRepositoryError.unavailable

            case .httpStatus(404, let body):
                throw Self.failure(forNotFound: body)

            case .httpStatus:
                throw DeparturesRepositoryError.unavailable

            case .invalidURL:
                throw DeparturesRepositoryError.unexpected
            }
        } catch {
            throw DeparturesRepositoryError.unexpected
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
            return .unavailable
        }

        return .unknownStation(role)
    }
}
