import Testing
@testable import DeparturesFeature

@Suite
struct DepartureRouteTests {
    private let route = DepartureRoute(
        origin: DepartureRoute.Station(id: "brzeg", name: "Brzeg"),
        destination: DepartureRoute.Station(id: "wroclaw", name: "Wrocław Główny")
    )

    @Test
    func aRouteQueriesFromItsOriginTowardsItsDestination() {
        #expect(
            DepartureQuery(route)
                == DepartureQuery(stationID: "brzeg", towardsStationID: "wroclaw")
        )
    }

    @Test
    func aReversedRouteRunsFromItsDestinationBackToItsOrigin() {
        #expect(route.reversed.origin == route.destination)
        #expect(route.reversed.destination == route.origin)
        #expect(route.reversed.reversed == route)
        #expect(
            DepartureQuery(route.reversed)
                == DepartureQuery(stationID: "wroclaw", towardsStationID: "brzeg")
        )
    }

    @Test
    func anUnknownStationRoleNamesTheStationOfTheRoute() {
        #expect(route.station(for: .origin).id == "brzeg")
        #expect(route.station(for: .onward).id == "wroclaw")
    }
}
