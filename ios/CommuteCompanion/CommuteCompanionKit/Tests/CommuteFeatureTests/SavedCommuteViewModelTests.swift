import Foundation
import Testing
@testable import CommuteFeature

@MainActor
@Suite
struct SavedCommuteViewModelTests {

    @Test
    func anAbsentFileLeavesTheCommuteNotConfigured() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        let viewModel = makeViewModel(directory: directory)

        await viewModel.load()

        #expect(viewModel.state == .notConfigured)
    }

    @Test
    func aSavedCommuteLoadsIntoTheConfiguredState() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        let commute = try #require(
            SavedCommute(home: .brzeg, destination: .wroclaw)
        )
        try await SavedCommuteStore(directory: directory).save(commute)
        let viewModel = makeViewModel(directory: directory)

        await viewModel.load()

        #expect(viewModel.state == .configured(commute))
    }

    @Test
    func corruptBytesFailAsUnusableRatherThanNotConfigured() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(Data("{ not json".utf8), in: directory)
        let viewModel = makeViewModel(directory: directory)

        await viewModel.load()

        #expect(viewModel.state == .failure(.unusable))
    }

    @Test
    func aDocumentNamingOneStationTwiceAlsoFailsAsUnusable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(sameStationFileData(schemaVersion: 1), in: directory)
        let viewModel = makeViewModel(directory: directory)

        await viewModel.load()

        #expect(viewModel.state == .failure(.unusable))
    }

    @Test
    func anUnrecognisedSchemaVersionAlsoFailsAsUnusable() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(commuteFileData(schemaVersion: 99), in: directory)
        let viewModel = makeViewModel(directory: directory)

        await viewModel.load()

        #expect(viewModel.state == .failure(.unusable))
    }
}

@MainActor
private func makeViewModel(directory: URL) -> SavedCommuteViewModel {
    SavedCommuteViewModel(store: SavedCommuteStore(directory: directory))
}
