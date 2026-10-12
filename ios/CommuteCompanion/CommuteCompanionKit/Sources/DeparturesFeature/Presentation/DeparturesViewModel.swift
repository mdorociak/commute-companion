import Foundation
import Observation

enum DeparturesViewFailure: Equatable, Sendable {
    case unreachable
    case serverFailure
    case invalidData
    case unknownStation(DepartureStationRole)
    case unexpected
}

enum DeparturesViewState: Equatable, Sendable {
    case idle
    case loading
    case loaded([Departure], fetchedAt: Date)
    case refreshFailed(
        [Departure],
        fetchedAt: Date,
        DeparturesViewFailure
    )
    case empty
    case failure(DeparturesViewFailure)
}

@MainActor
@Observable
final class DeparturesViewModel {
    private let query: DepartureQuery
    private let repository: any DeparturesRepository
    private let now: () -> Date
    @ObservationIgnored private var latestLoad = 0

    private(set) var state: DeparturesViewState = .idle

    init(
        query: DepartureQuery,
        repository: any DeparturesRepository,
        now: @escaping () -> Date
    ) {
        self.query = query
        self.repository = repository
        self.now = now
    }

    func load() async {
        latestLoad += 1
        let thisLoad = latestLoad

        switch state {
        case .loaded(let departures, let fetchedAt),
             .refreshFailed(let departures, let fetchedAt, _):
            state = .loaded(departures, fetchedAt: fetchedAt)
        case .idle, .loading, .empty, .failure:
            state = .loading
        }

        do {
            let departures = try await repository.fetchDepartures(
                query: query
            )

            try Task.checkCancellation()
            guard thisLoad == latestLoad else { return }

            state = departures.isEmpty
                ? .empty
                : .loaded(departures, fetchedAt: now())

        } catch is CancellationError {
            // Cancellation is not a user-facing failure.

        } catch let error as DeparturesRepositoryError {
            guard !Task.isCancelled, thisLoad == latestLoad else { return }
            show(mapFailure(error))

        } catch {
            guard !Task.isCancelled, thisLoad == latestLoad else { return }
            show(.unexpected)
        }
    }

    private func show(_ failure: DeparturesViewFailure) {
        switch (state, failure) {
        case (_, .unknownStation):
            state = .failure(failure)
        case (.loaded(let departures, let fetchedAt), _),
             (.refreshFailed(let departures, let fetchedAt, _), _):
            state = .refreshFailed(departures, fetchedAt: fetchedAt, failure)
        case (.idle, _), (.loading, _), (.empty, _), (.failure, _):
            state = .failure(failure)
        }
    }

    private func mapFailure(
        _ error: DeparturesRepositoryError
    ) -> DeparturesViewFailure {
        switch error {
        case .unreachable:
            .unreachable
        case .serverFailure:
            .serverFailure
        case .invalidData:
            .invalidData
        case .unknownStation(let role):
            .unknownStation(role)
        case .unexpected:
            .unexpected
        }
    }
}
