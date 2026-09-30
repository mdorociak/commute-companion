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
    func anUnknownStationRoleNamesTheStationOfTheRoute() {
        #expect(route.station(for: .origin).id == "brzeg")
        #expect(route.station(for: .onward).id == "wroclaw")
    }
}
