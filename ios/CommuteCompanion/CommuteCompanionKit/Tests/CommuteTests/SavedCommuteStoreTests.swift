import Foundation
import Testing
@testable import Commute

@Suite
struct SavedCommuteStoreTests {

    @Test
    func aSavedCommuteLoadsBackUnchanged() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        let store = SavedCommuteStore(directory: directory)
        let commute = SavedCommute(home: .brzeg, destination: .wroclaw)

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

        await #expect(throws: SavedCommuteStoreError.corruptData) {
            try await store.load()
        }
    }

    @Test
    func anUnrecognisedSchemaVersionFailsAsIncompatibleRatherThanCorrupt() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        try writeCommuteFile(
            Data(
                #"""
                {
                  "schemaVersion": 99,
                  "commute": {
                    "home": { "stationID": "brzeg", "displayName": "Brzeg" },
                    "destination": {
                      "stationID": "wroclaw",
                      "displayName": "Wrocław Główny"
                    }
                  }
                }
                """#.utf8
            ),
            in: directory
        )
        let store = SavedCommuteStore(directory: directory)

        await #expect(throws: SavedCommuteStoreError.incompatibleSchemaVersion(99)) {
            try await store.load()
        }
    }

    @Test
    func theSecondSaveIsTheOneThatLoadsBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeDirectory(directory) }
        let store = SavedCommuteStore(directory: directory)
        let first = SavedCommute(home: .brzeg, destination: .wroclaw)
        let second = SavedCommute(home: .brzeg, destination: .opole)

        try await store.save(first)
        try await store.save(second)
        let loaded = try await store.load()

        #expect(loaded == .configured(second))
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SavedCommuteStoreTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

private func removeDirectory(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

private func writeCommuteFile(_ data: Data, in directory: URL) throws {
    try data.write(to: directory.appending(path: SavedCommuteStore.fileName))
}

private extension StationReference {
    static let brzeg = StationReference(
        stationID: "brzeg",
        displayName: "Brzeg"
    )
    static let wroclaw = StationReference(
        stationID: "wroclaw",
        displayName: "Wrocław Główny"
    )
    static let opole = StationReference(
        stationID: "opole",
        displayName: "Opole Główne"
    )
}
