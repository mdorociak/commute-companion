import Foundation
import APIClient

struct RemoteStationsRepository: StationsRepository {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func fetchStations(search: String?) async throws -> [Station] {
        let queryItems: [URLQueryItem]

        if let search, !search.isEmpty {
            queryItems = [
                URLQueryItem(name: "search", value: search)
            ]
        } else {
            queryItems = []
        }

        do {
            let dtos = try await apiClient.get(
                path: "api/v1/stations",
                queryItems: queryItems,
                as: [StationDTO].self
            )

            try Task.checkCancellation()

            return dtos.map { $0.toDomain() }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            if error.code == .cancelled {
                throw CancellationError()
            }

            throw StationsRepositoryError.unavailable
        } catch is DecodingError {
            throw StationsRepositoryError.invalidData
        } catch let error as APIError {
            switch error {
            case .invalidResponse:
                throw StationsRepositoryError.unavailable

            case .httpStatus:
                throw StationsRepositoryError.unavailable

            case .invalidURL:
                throw StationsRepositoryError.unexpected
            }
        } catch {
            throw StationsRepositoryError.unexpected
        }
    }
}
