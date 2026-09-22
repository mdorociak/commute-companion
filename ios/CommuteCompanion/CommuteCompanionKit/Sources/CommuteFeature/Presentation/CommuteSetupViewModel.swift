import Observation

public enum CommuteField: Equatable, Sendable {
    case home
    case destination
}

public enum CommuteSetupReason: Equatable, Sendable {
    case storedCommuteUnusable
    case replacingStoredCommute
    case stationNoLongerResolves(CommuteField)
}

public enum CommuteSaveState: Equatable, Sendable {
    case idle
    case saving
    case failed
}

@MainActor
@Observable
public final class CommuteSetupViewModel {
    private let store: SavedCommuteStore
    private let saved: (SavedCommute) -> Void

    public let reason: CommuteSetupReason?

    public private(set) var home: StationReference?
    public private(set) var destination: StationReference?
    public private(set) var saveState: CommuteSaveState = .idle

    public init(
        store: SavedCommuteStore,
        commute: SavedCommute? = nil,
        reason: CommuteSetupReason? = nil,
        saved: @escaping (SavedCommute) -> Void
    ) {
        self.store = store
        self.reason = reason
        self.saved = saved

        home = commute?.home
        destination = commute?.destination
    }

    public var canSave: Bool {
        saveState != .saving && commute != nil
    }

    public func select(_ station: StationReference, as field: CommuteField) {
        switch field {
        case .home:
            home = station

        case .destination:
            destination = station
        }

        if saveState == .failed {
            saveState = .idle
        }
    }

    public func save() async {
        guard saveState != .saving, let commute else { return }

        saveState = .saving

        do {
            try await store.save(commute)
        } catch {
            saveState = .failed
            return
        }

        saveState = .idle
        saved(commute)
    }

    private var commute: SavedCommute? {
        guard let home, let destination else { return nil }

        return SavedCommute(home: home, destination: destination)
    }
}
