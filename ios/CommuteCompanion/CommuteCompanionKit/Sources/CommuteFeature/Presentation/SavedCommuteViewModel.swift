import Observation

public enum SavedCommuteFailure: Equatable, Sendable {
    case unusable
    case unreadable
}

public enum SavedCommuteState: Equatable, Sendable {
    case idle
    case loading
    case notConfigured
    case configured(SavedCommute)
    case failure(SavedCommuteFailure)
}

@MainActor
@Observable
public final class SavedCommuteViewModel {
    private let store: SavedCommuteStore

    public private(set) var state: SavedCommuteState = .idle

    public init(store: SavedCommuteStore) {
        self.store = store
    }

    public func load() async {
        state = .loading

        let stored: StoredCommute

        do {
            stored = try await store.load()
        } catch {
            guard !Task.isCancelled else { return }
            state = .failure(mapFailure(error))
            return
        }

        guard !Task.isCancelled else { return }

        switch stored {
        case .notConfigured:
            state = .notConfigured

        case .configured(let commute):
            state = .configured(commute)
        }
    }

    private func mapFailure(_ error: SavedCommuteLoadError) -> SavedCommuteFailure {
        switch error {
        case .corruptData, .incompatibleSchemaVersion, .invalidCommute:
            .unusable

        case .unreadable:
            .unreadable
        }
    }
}
