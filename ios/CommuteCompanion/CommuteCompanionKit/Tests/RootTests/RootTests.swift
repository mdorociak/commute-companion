import Foundation
import Testing
@testable import Root

@MainActor @Test
func rootViewCanBeCreated() throws {
    let baseURL = try #require(URL(string: "https://example.com"))
    let commuteDirectory = FileManager.default.temporaryDirectory
        .appending(path: "RootTests-\(UUID().uuidString)")

    _ = RootView(baseURL: baseURL, commuteDirectory: commuteDirectory)
}
