import Observation

enum StationsViewFailure: Equatable, Sendable {
    case unavailable
    case invalidData
    case unexpected
}

enum StationsViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded([Station])
    case empty
    case failure(StationsViewFailure)
}

@MainActor
@Observable
final class StationsViewModel {
    private let repository: any StationsRepository

    var searchText = ""

    private(set) var state: StationsViewState = .idle

    init(repository: any StationsRepository) {
        self.repository = repository
    }

    func load() async {
        state = .loading

        do {
            let stations = try await repository.fetchStations(
                search: nil
            )

            try Task.checkCancellation()

            state = stations.isEmpty ? .empty : .loaded(stations)

        } catch is CancellationError {
            // Cancellation is not a user-facing failure.

        } catch let error as StationsRepositoryError {
            guard !Task.isCancelled else { return }
            state = .failure(mapFailure(error))

        } catch {
            guard !Task.isCancelled else { return }
            state = .failure(.unexpected)
        }
    }

    var filteredStations: [Station] {
        guard case let .loaded(stations) = state else { return [] }

        let query = normalizedSearchText

        guard !query.isEmpty else { return stations }

        return stations.filter { station in
            station.name.localizedCaseInsensitiveContains(query)
        }
    }

    var hasActiveSearch: Bool {
        !normalizedSearchText.isEmpty
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mapFailure(_ error: StationsRepositoryError) -> StationsViewFailure {
        switch error {
        case .unavailable:
            .unavailable
        case .invalidData:
            .invalidData
        case .unexpected:
            .unexpected
        }
    }
}
