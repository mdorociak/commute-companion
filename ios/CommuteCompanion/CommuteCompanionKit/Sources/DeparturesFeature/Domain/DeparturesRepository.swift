enum DepartureStationRole: Equatable, Sendable {
    case origin
    case onward
}

enum DeparturesRepositoryError: Error, Equatable, Sendable {
    case unavailable
    case invalidData
    case unknownStation(DepartureStationRole)
    case unexpected
}

protocol DeparturesRepository: Sendable {
    func fetchDepartures(stationID: String) async throws -> [Departure]
}
