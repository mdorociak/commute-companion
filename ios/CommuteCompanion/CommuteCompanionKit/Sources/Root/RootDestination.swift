import CommuteFeature

enum RootDestination: Equatable {
    case loading
    case configured(SavedCommute)
    case setup(CommuteSetupReason?)
    case unreadable

    init(_ state: SavedCommuteState) {
        switch state {
        case .idle, .loading:
            self = .loading

        case .configured(let commute):
            self = .configured(commute)

        case .notConfigured:
            self = .setup(nil)

        case .failure(.unusable):
            self = .setup(.storedCommuteUnusable)

        case .failure(.unreadable):
            self = .unreadable
        }
    }
}
