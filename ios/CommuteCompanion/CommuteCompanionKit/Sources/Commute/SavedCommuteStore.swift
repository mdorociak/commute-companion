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
        self.fileURL = directory.appending(path: SavedCommuteStore.fileName)
    }

    func save(_ commute: SavedCommute) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(commute)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw SavedCommuteStoreError.unwritable
        }
    }

    func load() throws -> StoredCommute {
        guard FileManager.default.fileExists(
            atPath: fileURL.path(percentEncoded: false)
        ) else {
            return .notConfigured
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SavedCommuteStoreError.unreadable
        }

        let decoder = JSONDecoder()

        guard let envelope = try? decoder.decode(SchemaEnvelope.self, from: data) else {
            throw SavedCommuteStoreError.corruptData
        }

        guard envelope.schemaVersion == SavedCommute.currentSchemaVersion else {
            throw SavedCommuteStoreError.incompatibleSchemaVersion(envelope.schemaVersion)
        }

        guard let commute = try? decoder.decode(SavedCommute.self, from: data) else {
            throw SavedCommuteStoreError.corruptData
        }

        return .configured(commute)
    }
}

private struct SchemaEnvelope: Decodable {
    let schemaVersion: Int
}
