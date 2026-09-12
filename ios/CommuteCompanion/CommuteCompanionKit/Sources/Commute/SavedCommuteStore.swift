import Foundation

enum StoredCommute: Equatable, Sendable {
    case notConfigured
    case configured(SavedCommute)
}

enum SavedCommuteStoreError: Error, Equatable, Sendable {
    case unreadable
    case unwritable
    case corruptData
    case incompatibleSchemaVersion(Int)
}

actor SavedCommuteStore {
    static let fileName = "saved-commute.json"

    private let directory: URL
    private let fileURL: URL

    init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appending(path: Self.fileName)
    }

    func save(_ commute: SavedCommute) throws(SavedCommuteStoreError) {
        let envelope = StoredEnvelope(
            schemaVersion: StoredEnvelope.currentSchemaVersion,
            commute: commute
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

    func load() throws(SavedCommuteStoreError) -> StoredCommute {
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

        let envelope: StoredEnvelope

        do {
            envelope = try JSONDecoder().decode(StoredEnvelope.self, from: data)
        } catch {
            throw .corruptData
        }

        guard envelope.schemaVersion == StoredEnvelope.currentSchemaVersion else {
            throw .incompatibleSchemaVersion(envelope.schemaVersion)
        }

        return .configured(envelope.commute)
    }
}

private struct StoredEnvelope: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let commute: SavedCommute
}
