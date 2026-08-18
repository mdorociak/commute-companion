import Observation

enum DeparturesViewFailure: Equatable, Sendable {
    case unavailable
    case invalidData
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
    private let stationID: String
    private let repository: any DeparturesRepository

    private(set) var state: DeparturesViewState = .idle

    init(
        stationID: String,
        repository: any DeparturesRepository
    ) {
        self.stationID = stationID
        self.repository = repository
    }

    func load() async {
        state = .loading

        do {
            let departures = try await repository.fetchDepartures(
                stationID: stationID
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
        case .unavailable:
            .unavailable
        case .invalidData:
            .invalidData
        case .unexpected:
            .unexpected
        }
    }
}
