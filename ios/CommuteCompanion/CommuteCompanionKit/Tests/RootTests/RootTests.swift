import Foundation
import Testing
import CommuteFeature
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
    let commute = try #require(
        SavedCommute(
            home: StationReference(stationID: "brzeg", displayName: "Brzeg"),
            destination: StationReference(
                stationID: "wroclaw",
                displayName: "Wrocław Główny"
            )
        )
    )

    #expect(RootDestination(.idle) == .loading)
    #expect(RootDestination(.loading) == .loading)
    #expect(RootDestination(.notConfigured) == .setup(nil))
    #expect(RootDestination(.configured(commute)) == .configured(commute))
    #expect(RootDestination(.failure(.unusable)) == .setup(.storedCommuteUnusable))
    #expect(RootDestination(.failure(.unreadable)) == .unreadable)
}
