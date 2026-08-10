import Foundation
import Testing
@testable import Root

@MainActor @Test
func rootViewCanBeCreated() throws {
    let baseURL = try #require(URL(string: "https://example.com"))
    _ = RootView(baseURL: baseURL)
}
