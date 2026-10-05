import Foundation
import APIClient

struct RemoteStationsRepository: StationsRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchStations() async throws -> [Station] {
        do {
            let dtos = try await apiClient.get(
                path: "api/v1/stations",
                as: [StationDTO].self
            )

            try Task.checkCancellation()

            return dtos.map { $0.toDomain() }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as APIError {
            throw Self.failure(for: error)
        } catch {
            throw StationsRepositoryError.unexpected
        }
    }

    private static func failure(for error: APIError) -> StationsRepositoryError {
        switch error {
        case .unreachable:
            .unreachable

        case .httpStatus:
            .serverFailure

        case .invalidResponse, .decoding:
            .invalidData

        case .invalidURL:
            .unexpected
        }
    }
}
