import Foundation
import Testing
@testable import CommuteFeature

@Suite
struct SavedCommuteStoreTests {

    @Test
    func aSavedCommuteLoadsBackUnchanged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        let store = SavedCommuteStore(directory: directory)
        let commute = try #require(
            SavedCommute(home: .brzeg, destination: .wroclaw)
        )

        try await store.save(commute)
        let loaded = try await store.load()

        #expect(loaded == .configured(commute))
    }

    @Test
    func anAbsentFileLoadsAsNotConfiguredRatherThanFailing() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        let store = SavedCommuteStore(directory: directory)

        let loaded = try await store.load()

        #expect(loaded == .notConfigured)
    }

    @Test
    func corruptBytesFailAndAreNeverReportedAsNotConfigured() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(Data("{ not json".utf8), in: directory)
        let store = SavedCommuteStore(directory: directory)

        await #expect(throws: SavedCommuteLoadError.corruptData) {
            try await store.load()
        }
    }

    @Test
    func anUnrecognisedSchemaVersionFailsAsIncompatibleRatherThanCorrupt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(commuteFileData(schemaVersion: 99), in: directory)
        let store = SavedCommuteStore(directory: directory)

        await #expect(throws: SavedCommuteLoadError.incompatibleSchemaVersion(99)) {
            try await store.load()
        }
    }

    @Test
    func anUnrecognisedVersionIsReportedEvenWhenThePayloadIsRestructured() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(restructuredFileData(schemaVersion: 99), in: directory)
        let store = SavedCommuteStore(directory: directory)

        await #expect(throws: SavedCommuteLoadError.incompatibleSchemaVersion(99)) {
            try await store.load()
        }
    }

    @Test
    func aRestructuredPayloadAtTheCurrentVersionIsCorrupt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(restructuredFileData(schemaVersion: 1), in: directory)
        let store = SavedCommuteStore(directory: directory)

        await #expect(throws: SavedCommuteLoadError.corruptData) {
            try await store.load()
        }
    }

    @Test
    func aDocumentNamingOneStationTwiceIsNotACommute() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(sameStationFileData(schemaVersion: 1), in: directory)
        let store = SavedCommuteStore(directory: directory)

        await #expect(throws: SavedCommuteLoadError.invalidCommute) {
            try await store.load()
        }
    }

    @Test
    func theSecondSaveIsTheOneThatLoadsBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        let store = SavedCommuteStore(directory: directory)
        let first = try #require(
            SavedCommute(home: .brzeg, destination: .wroclaw)
        )
        let second = try #require(
            SavedCommute(home: .brzeg, destination: .opole)
        )

        try await store.save(first)
        try await store.save(second)
        let loaded = try await store.load()

        #expect(loaded == .configured(second))
    }
}
