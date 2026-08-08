import Observation
import Testing
@testable import StationsFeature

@MainActor
@Suite
struct StationsViewModelTests {

    @Test
    func loadTransitionsFromIdleThroughLoadingToLoaded() async {
        let station = Station(
            id: "brzeg",
            name: "Brzeg",
            code: nil
        )
        let repository = ImmediateStationsRepository(
            result: .success([station])
        )
        let viewModel = StationsViewModel(repository: repository)

        #expect(viewModel.state == .idle)

        viewModel.load()

        #expect(viewModel.state == .loading)

        await waitForState(.loaded([station]), in: viewModel)
    }

    @Test
    func loadMapsSuccessfulEmptyResultToEmpty() async {
        let repository = ImmediateStationsRepository(
            result: .success([])
        )
        let viewModel = StationsViewModel(repository: repository)

        viewModel.load()

        await waitForState(.empty, in: viewModel)
    }

    @Test
    func loadMapsRepositoryErrorsToViewFailures() async {
        let cases: [(StationsRepositoryError, StationsViewFailure)] = [
            (.unavailable, .unavailable),
            (.invalidData, .invalidData),
            (.unexpected, .unexpected),
        ]

        for (repositoryError, viewFailure) in cases {
            let repository = ImmediateStationsRepository(
                result: .failure(repositoryError)
            )
            let viewModel = StationsViewModel(repository: repository)

            viewModel.load()

            await waitForState(.failure(viewFailure), in: viewModel)
        }
    }

    @Test
    func newerLoadCancelsOlderLoadAndKeepsNewestResult() async {
        let repository = ControlledStationsRepository()
        let viewModel = StationsViewModel(repository: repository)
        let oldStation = Station(
            id: "old",
            name: "Old result",
            code: nil
        )
        let newStation = Station(
            id: "new",
            name: "New result",
            code: nil
        )

        viewModel.load(search: "old")
        await repository.waitUntilRequested(search: "old")

        viewModel.load(search: "new")
        await repository.waitUntilRequested(search: "new")
        await repository.waitUntilCancelled(search: "old")

        await repository.complete(
            search: "new",
            with: .success([newStation])
        )
        await waitForState(.loaded([newStation]), in: viewModel)

        await repository.complete(
            search: "old",
            with: .success([oldStation])
        )
        await Task.yield()

        #expect(viewModel.state == .loaded([newStation]))
    }
}

private struct ImmediateStationsRepository: StationsRepository {
    let result: Result<[Station], StationsRepositoryError>

    func fetchStations(search: String?) async throws -> [Station] {
        try result.get()
    }
}

private actor ControlledStationsRepository: StationsRepository {
    typealias Response = Result<[Station], any Error>

    private var pendingRequests: [
        String: CheckedContinuation<[Station], any Error>
    ] = [:]
    private var requestWaiters: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]
    private var cancelledSearches: Set<String> = []
    private var cancellationWaiters: [
        String: [CheckedContinuation<Void, Never>]
    ] = [:]

    func fetchStations(search: String?) async throws -> [Station] {
        let search = search ?? ""

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequests[search] = continuation
                resumeWaiters(for: search, in: &requestWaiters)
            }
        } onCancel: {
            Task {
                await self.recordCancellation(search: search)
            }
        }
    }

    func waitUntilRequested(search: String) async {
        guard pendingRequests[search] == nil else { return }

        await withCheckedContinuation { continuation in
            requestWaiters[search, default: []].append(continuation)
        }
    }

    func waitUntilCancelled(search: String) async {
        guard !cancelledSearches.contains(search) else { return }

        await withCheckedContinuation { continuation in
            cancellationWaiters[search, default: []].append(continuation)
        }
    }

    func complete(search: String, with response: Response) {
        guard let continuation = pendingRequests.removeValue(
            forKey: search
        ) else {
            Issue.record("No pending request for \(search)")
            return
        }

        continuation.resume(with: response)
    }

    private func recordCancellation(search: String) {
        cancelledSearches.insert(search)
        resumeWaiters(for: search, in: &cancellationWaiters)
    }

    private func resumeWaiters(
        for search: String,
        in waiters: inout [String: [CheckedContinuation<Void, Never>]]
    ) {
        let continuations = waiters.removeValue(forKey: search) ?? []

        for continuation in continuations {
            continuation.resume()
        }
    }
}

@MainActor
private func waitForState(
    _ expectedState: StationsViewState,
    in viewModel: StationsViewModel
) async {
    while viewModel.state != expectedState {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = viewModel.state
            } onChange: {
                continuation.resume()
            }
        }
    }
}
