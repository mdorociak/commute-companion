
protocol StationsRepository: Sendable {
    func fetchStations(search: String?) async throws -> [Station]
}

