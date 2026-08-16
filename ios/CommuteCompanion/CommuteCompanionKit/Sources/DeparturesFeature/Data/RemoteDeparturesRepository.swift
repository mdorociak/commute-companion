import Foundation
import APIClient

struct RemoteDeparturesRepository: DeparturesRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchDepartures(stationID: String) async throws -> [Departure] {
        do {
            let dtos = try await apiClient.get(
                path: "api/v1/stations/\(stationID)/departures",
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

            case .httpStatus:
                throw DeparturesRepositoryError.unavailable

            case .invalidURL:
                throw DeparturesRepositoryError.unexpected
            }
        } catch {
            throw DeparturesRepositoryError.unexpected
        }
    }
}
