
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
            queryItems = [URLQueryItem(name: "search", value: search)]
        }
        else {
            queryItems = []
        }
        
        let dtos = try await apiClient.get(path: "api/v1/stations", queryItems: queryItems, as: [StationDTO].self)
        return dtos.map { $0.toDomain() }
    }
}
