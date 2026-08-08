
enum StationsRepositoryError: Error, Equatable, Sendable {
    case unavailable
    case invalidData
    case unexpected
}

protocol StationsRepository: Sendable {
    func fetchStations(search: String?) async throws -> [Station]
}
