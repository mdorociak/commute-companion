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

    @ObservationIgnored
    private var loadTask: Task<Void, Never>?

    @ObservationIgnored
    private var requestID: UInt = 0

    private(set) var state: StationsViewState = .idle

    init(repository: any StationsRepository) {
        self.repository = repository
    }

    deinit {
        loadTask?.cancel()
    }

    func load(search: String? = nil) {
        loadTask?.cancel()

        requestID &+= 1
        let currentRequestID = requestID

        // Capture the dependency independently of self.
        let repository = repository

        state = .loading

        loadTask = Task { [weak self] in
            do {
                let stations = try await repository.fetchStations(
                    search: search
                )

                guard !Task.isCancelled else { return }

                guard let self,
                      requestID == currentRequestID
                else { return }

                state = stations.isEmpty ? .empty : .loaded(stations)

                loadTask = nil

            } catch is CancellationError {
                // Cancellation is not a user-facing failure.

            } catch let error as StationsRepositoryError {
                guard let self,
                      requestID == currentRequestID
                else {
                    return
                }

                state = .failure(mapFailure(error))
                loadTask = nil

            } catch {
                guard let self,
                      requestID == currentRequestID
                else {
                    return
                }

                state = .failure(.unexpected)
                loadTask = nil
            }
        }
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil

        // Invalidate any result from work that fails to honor cancellation.
        requestID &+= 1
    }

    private func mapFailure(
        _ error: StationsRepositoryError
    ) -> StationsViewFailure {
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
