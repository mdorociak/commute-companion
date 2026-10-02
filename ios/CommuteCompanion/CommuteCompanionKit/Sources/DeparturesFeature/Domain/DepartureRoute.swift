public struct DepartureRoute: Hashable, Sendable {
    public struct Station: Hashable, Sendable {
        public let id: String
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    public let origin: Station
    public let destination: Station

    public init(origin: Station, destination: Station) {
        self.origin = origin
        self.destination = destination
    }

    public var reversed: DepartureRoute {
        DepartureRoute(origin: destination, destination: origin)
    }

    func station(for role: DepartureStationRole) -> Station {
        switch role {
        case .origin:
            origin

        case .onward:
            destination
        }
    }
}

extension DepartureQuery {
    init(_ route: DepartureRoute) {
        self.init(
            stationID: route.origin.id,
            towardsStationID: route.destination.id
        )
    }
}
