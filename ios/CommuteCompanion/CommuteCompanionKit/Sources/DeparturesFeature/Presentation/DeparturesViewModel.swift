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
    case loaded([Departure])
    case empty
    case failure(DeparturesViewFailure)
}

@MainActor
@Observable
final class DeparturesViewModel {
    private let query: DepartureQuery
    private let repository: any DeparturesRepository

    private(set) var state: DeparturesViewState = .idle

    init(
        query: DepartureQuery,
        repository: any DeparturesRepository
    ) {
        self.query = query
        self.repository = repository
    }

    func load() async {
        state = .loading

        do {
            let departures = try await repository.fetchDepartures(
                query: query
            )

            try Task.checkCancellation()

            state = departures.isEmpty ? .empty : .loaded(departures)

        } catch is CancellationError {
            // Cancellation is not a user-facing failure.

        } catch let error as DeparturesRepositoryError {
            guard !Task.isCancelled else { return }
            state = .failure(mapFailure(error))

        } catch {
            guard !Task.isCancelled else { return }
            state = .failure(.unexpected)
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
