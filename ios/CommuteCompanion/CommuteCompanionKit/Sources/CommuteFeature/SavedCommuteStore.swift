import Foundation

public enum StoredCommute: Equatable, Sendable {
    case notConfigured
    case configured(SavedCommute)
}

public enum SavedCommuteLoadError: Error, Equatable, Sendable {
    case unreadable
    case corruptData
    case incompatibleSchemaVersion(Int)
    case invalidCommute
}

public enum SavedCommuteSaveError: Error, Equatable, Sendable {
    case unwritable
}

public actor SavedCommuteStore {
    static let fileName = "saved-commute.json"

    private let directory: URL
    private let fileURL: URL

    public init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appending(path: Self.fileName)
    }

    public func save(_ commute: SavedCommute) throws(SavedCommuteSaveError) {
        let envelope = StoredEnvelope(
            schemaVersion: StoredEnvelope.currentSchemaVersion,
            commute: SavedCommuteDTO(commute)
        )

        do {
            let data = try JSONEncoder().encode(envelope)

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw .unwritable
        }
    }

    public func load() throws(SavedCommuteLoadError) -> StoredCommute {
        guard FileManager.default.fileExists(
            atPath: fileURL.path(percentEncoded: false)
        ) else {
            return .notConfigured
        }

        let data: Data

        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw .unreadable
        }

        let decoder = JSONDecoder()

        let version: StoredVersion

        do {
            version = try decoder.decode(StoredVersion.self, from: data)
        } catch {
            throw .corruptData
        }

        guard version.schemaVersion == StoredEnvelope.currentSchemaVersion else {
            throw .incompatibleSchemaVersion(version.schemaVersion)
        }

        let envelope: StoredEnvelope

        do {
            envelope = try decoder.decode(StoredEnvelope.self, from: data)
        } catch {
            throw .corruptData
        }

        guard let commute = envelope.commute.savedCommute else {
            throw .invalidCommute
        }

        return .configured(commute)
    }
}

private struct StoredVersion: Decodable {
    let schemaVersion: Int
}

private struct StoredEnvelope: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let commute: SavedCommuteDTO
}

private struct SavedCommuteDTO: Codable {
    let home: StationReferenceDTO
    let destination: StationReferenceDTO

    init(_ commute: SavedCommute) {
        home = StationReferenceDTO(commute.home)
        destination = StationReferenceDTO(commute.destination)
    }

    var savedCommute: SavedCommute? {
        SavedCommute(
            home: home.stationReference,
            destination: destination.stationReference
        )
    }
}

private struct StationReferenceDTO: Codable {
    let stationID: String
    let displayName: String

    init(_ reference: StationReference) {
        stationID = reference.stationID
        displayName = reference.displayName
    }

    var stationReference: StationReference {
        StationReference(stationID: stationID, displayName: displayName)
    }
}
