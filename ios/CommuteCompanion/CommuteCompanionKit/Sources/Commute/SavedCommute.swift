struct StationReference: Codable, Equatable, Sendable {
    let stationID: String
    let displayName: String
}

struct SavedCommute: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = SavedCommute.currentSchemaVersion
    let home: StationReference
    let destination: StationReference
}
