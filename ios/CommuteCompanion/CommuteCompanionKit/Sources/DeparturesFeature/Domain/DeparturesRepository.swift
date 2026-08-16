enum DeparturesRepositoryError: Error, Equatable, Sendable {
    case unavailable
    case invalidData
    case unexpected
}

protocol DeparturesRepository: Sendable {
    func fetchDepartures(stationID: String) async throws -> [Departure]
}
