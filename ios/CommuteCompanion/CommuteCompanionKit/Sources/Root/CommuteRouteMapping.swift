import CommuteFeature
import DeparturesFeature

extension DepartureRoute {
    init(_ commute: SavedCommute) {
        self.init(
            origin: DepartureRoute.Station(
                id: commute.home.stationID,
                name: commute.home.displayName
            ),
            destination: DepartureRoute.Station(
                id: commute.destination.stationID,
                name: commute.destination.displayName
            )
        )
    }
}

extension SavedCommute {
    func field(forStationID stationID: String) -> CommuteField? {
        if home.stationID == stationID {
            return .home
        }

        if destination.stationID == stationID {
            return .destination
        }

        return nil
    }
}
