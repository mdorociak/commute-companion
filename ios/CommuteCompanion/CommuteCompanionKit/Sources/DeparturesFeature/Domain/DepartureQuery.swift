struct DepartureQuery: Equatable, Sendable {
    let stationID: String
    let towardsStationID: String?

    init(stationID: String, towardsStationID: String? = nil) {
        self.stationID = stationID
        self.towardsStationID = towardsStationID
    }
}
