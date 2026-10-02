import Foundation
import Testing
import CommuteFeature
import DeparturesFeature
@testable import Root

@MainActor @Test
func rootViewCanBeCreated() throws {
    let baseURL = try #require(URL(string: "https://example.com"))
    let commuteDirectory = FileManager.default.temporaryDirectory
        .appending(path: "RootTests-\(UUID().uuidString)")

    _ = RootView(baseURL: baseURL, commuteDirectory: commuteDirectory)
}

@Test
func eachSavedCommuteStateRoutesToItsOwnDestination() throws {
    let commute = try makeCommute()

    #expect(RootDestination(.idle) == .loading)
    #expect(RootDestination(.loading) == .loading)
    #expect(RootDestination(.notConfigured) == .setup(nil))
    #expect(RootDestination(.configured(commute)) == .configured(commute))
    #expect(RootDestination(.failure(.unusable)) == .setup(.storedCommuteUnusable))
    #expect(RootDestination(.failure(.unreadable)) == .unreadable)
}

@Test
func aSavedCommuteBecomesARouteFromHomeTowardsDestination() throws {
    let route = try DepartureRoute(makeCommute())

    #expect(route.origin == DepartureRoute.Station(id: "brzeg", name: "Brzeg"))
    #expect(
        route.destination
            == DepartureRoute.Station(id: "wroclaw", name: "Wrocław Główny")
    )
}

@Test
func aStationReportedByTheBoardNamesTheFieldItBelongsTo() throws {
    let commute = try makeCommute()

    #expect(commute.field(forStationID: "brzeg") == .home)
    #expect(commute.field(forStationID: "wroclaw") == .destination)
    #expect(commute.field(forStationID: "opole") == nil)
}

@Test
func aStationReportedByAReversedBoardStillNamesItsOwnField() throws {
    let commute = try makeCommute()
    let reversed = DepartureRoute(commute).reversed

    #expect(commute.field(forStationID: reversed.origin.id) == .destination)
    #expect(commute.field(forStationID: reversed.destination.id) == .home)
}

private func makeCommute() throws -> SavedCommute {
    try #require(
        SavedCommute(
            home: StationReference(stationID: "brzeg", displayName: "Brzeg"),
            destination: StationReference(
                stationID: "wroclaw",
                displayName: "Wrocław Główny"
            )
        )
    )
}
