
enum StationsRepositoryError: Error, Equatable, Sendable {
    case unreachable
    case serverFailure
    case invalidData
    case unexpected
}

protocol StationsRepository: Sendable {
    func fetchStations() async throws -> [Station]
}
