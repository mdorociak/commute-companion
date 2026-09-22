public struct StationReference: Equatable, Sendable {
    public let stationID: String
    public let displayName: String

    public init(stationID: String, displayName: String) {
        self.stationID = stationID
        self.displayName = displayName
    }
}

public struct SavedCommute: Equatable, Sendable {
    public let home: StationReference
    public let destination: StationReference

    public init?(home: StationReference, destination: StationReference) {
        guard home.stationID != destination.stationID else { return nil }

        self.home = home
        self.destination = destination
    }
}
