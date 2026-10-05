enum DepartureStationRole: Equatable, Sendable {
    case origin
    case onward
}

enum DeparturesRepositoryError: Error, Equatable, Sendable {
    case unreachable
    case serverFailure
    case invalidData
    case unknownStation(DepartureStationRole)
    case unexpected
}

protocol DeparturesRepository: Sendable {
    func fetchDepartures(query: DepartureQuery) async throws -> [Departure]
}
