struct StationReference: Codable, Equatable, Sendable {
    let stationID: String
    let displayName: String
}

struct SavedCommute: Codable, Equatable, Sendable {
    let home: StationReference
    let destination: StationReference
}
