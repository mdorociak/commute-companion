import Foundation
@testable import CommuteFeature

func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "CommuteFeatureTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
}

func makeTemporaryFile() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "CommuteFeatureTests-\(UUID().uuidString).blocked")
    try Data().write(to: url)
    return url
}

func remove(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

func writeCommuteFile(_ data: Data, in directory: URL) throws {
    try data.write(to: directory.appending(path: SavedCommuteStore.fileName))
}

func commuteFileData(schemaVersion: Int) -> Data {
    Data(
        """
        {
          "schemaVersion": \(schemaVersion),
          "commute": {
            "home": { "stationID": "brzeg", "displayName": "Brzeg" },
            "destination": {
              "stationID": "wroclaw",
              "displayName": "Wrocław Główny"
            }
          }
        }
        """.utf8
    )
}

func sameStationFileData(schemaVersion: Int) -> Data {
    Data(
        """
        {
          "schemaVersion": \(schemaVersion),
          "commute": {
            "home": { "stationID": "brzeg", "displayName": "Brzeg" },
            "destination": { "stationID": "brzeg", "displayName": "Brzeg" }
          }
        }
        """.utf8
    )
}

func restructuredFileData(schemaVersion: Int) -> Data {
    Data(
        """
        {
          "schemaVersion": \(schemaVersion),
          "legs": [
            { "from": "brzeg", "to": "wroclaw" }
          ]
        }
        """.utf8
    )
}

extension StationReference {
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
