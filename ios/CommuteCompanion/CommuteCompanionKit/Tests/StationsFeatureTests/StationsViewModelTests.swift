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
        let repository = ControlledStationsRepository()
        let viewModel = StationsViewModel(repository: repository)

        #expect(viewModel.state == .idle)

        let loadTask = Task {
            await viewModel.load()
        }

        await repository.waitUntilRequested(search: "")

        #expect(viewModel.state == .loading)

        await repository.complete(
            search: "",
            with: .success([station])
        )
        await loadTask.value

        #expect(viewModel.state == .loaded([station]))
    }

    @Test
    func loadMapsSuccessfulEmptyResultToEmpty() async {
        let repository = ImmediateStationsRepository(
            result: .success([])
        )
        let viewModel = StationsViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.state == .empty)
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

            await viewModel.load()

            #expect(viewModel.state == .failure(viewFailure))
        }
    }

    @Test
    func cancelledLoadCannotOverwriteNewerResult() async {
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

        let oldLoadTask = Task {
            await viewModel.load(search: "old")
        }
        await repository.waitUntilRequested(search: "old")

        oldLoadTask.cancel()
        await repository.waitUntilCancelled(search: "old")

        let newLoadTask = Task {
            await viewModel.load(search: "new")
        }
        await repository.waitUntilRequested(search: "new")

        await repository.complete(
            search: "new",
            with: .success([newStation])
        )
        await newLoadTask.value

        #expect(viewModel.state == .loaded([newStation]))

        await repository.complete(
            search: "old",
            with: .success([oldStation])
        )
        await oldLoadTask.value

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
