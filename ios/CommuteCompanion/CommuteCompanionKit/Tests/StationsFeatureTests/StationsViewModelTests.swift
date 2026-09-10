import Testing
@testable import StationsFeature

@MainActor
@Suite
struct StationsViewModelTests {

    @Test
    func loadTransitionsFromIdleThroughLoadingToLoadedAndPreservesOrder() async {
        let wroclaw = Station(
            id: "wroclaw",
            name: "Wrocław Główny",
            code: nil
        )
        let brzeg = Station(
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

        await repository.waitUntilRequested()

        #expect(viewModel.state == .loading)

        await repository.complete(with: .success([wroclaw, brzeg]))
        await loadTask.value

        #expect(
            viewModel.state == .loaded([
                wroclaw,
                brzeg,
            ])
        )
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
    func loadMapsUnrelatedErrorToUnexpectedFailure() async {
        let viewModel = StationsViewModel(
            repository: UnrelatedErrorStationsRepository()
        )

        await viewModel.load()

        #expect(viewModel.state == .failure(.unexpected))
    }

    @Test
    func searchFiltersLoadedStationsCaseInsensitivelyAndTrimsWhitespace() async {
        let brzeg = Station(
            id: "brzeg",
            name: "Brzeg",
            code: nil
        )
        let brzegDolny = Station(
            id: "brzeg-dolny",
            name: "Brzeg Dolny",
            code: nil
        )
        let wroclaw = Station(
            id: "wroclaw",
            name: "Wrocław Główny",
            code: nil
        )
        let viewModel = StationsViewModel(
            repository: ImmediateStationsRepository(
                result: .success([brzeg, brzegDolny, wroclaw])
            )
        )

        await viewModel.load()
        viewModel.searchText = "  bRzEg  "

        #expect(viewModel.hasActiveSearch)
        #expect(viewModel.filteredStations == [brzeg, brzegDolny])
    }

    @Test
    func emptySearchRestoresAllLoadedStations() async {
        let stations = [
            Station(id: "brzeg", name: "Brzeg", code: nil),
            Station(id: "wroclaw", name: "Wrocław Główny", code: nil),
        ]
        let viewModel = StationsViewModel(
            repository: ImmediateStationsRepository(
                result: .success(stations)
            )
        )

        await viewModel.load()
        viewModel.searchText = "Brzeg"
        #expect(viewModel.filteredStations.count == 1)

        viewModel.searchText = " \n "

        #expect(!viewModel.hasActiveSearch)
        #expect(viewModel.filteredStations == stations)
    }

    @Test
    func unmatchedSearchReturnsNoVisibleStations() async {
        let viewModel = StationsViewModel(
            repository: ImmediateStationsRepository(
                result: .success([
                    Station(id: "brzeg", name: "Brzeg", code: nil)
                ])
            )
        )

        await viewModel.load()
        viewModel.searchText = "Opole"

        #expect(viewModel.hasActiveSearch)
        #expect(viewModel.filteredStations.isEmpty)
    }

    @Test
    func searchMatchesAStationNameTypedWithoutDiacritics() async {
        let wroclaw = Station(
            id: "wroclaw",
            name: "Wrocław Główny",
            code: nil
        )
        let brzeg = Station(
            id: "brzeg",
            name: "Brzeg",
            code: nil
        )
        let viewModel = StationsViewModel(
            repository: ImmediateStationsRepository(
                result: .success([brzeg, wroclaw])
            )
        )

        await viewModel.load()
        viewModel.searchText = "wroclaw"

        #expect(viewModel.hasActiveSearch)
        #expect(viewModel.filteredStations == [wroclaw])
    }

    @Test(arguments: LateRepositoryCompletion.allCases)
    fileprivate func cancelledLoadCannotPublishLateRepositoryCompletion(
        _ lateCompletion: LateRepositoryCompletion
    ) async {
        let repository = ControlledStationsRepository()
        let viewModel = StationsViewModel(repository: repository)
        let station = Station(
            id: "brzeg",
            name: "Brzeg",
            code: nil
        )

        let loadTask = Task {
            await viewModel.load()
        }
        await repository.waitUntilRequested()

        loadTask.cancel()
        await repository.waitUntilCancelled()

        await repository.complete(
            with: lateCompletion.response(station: station)
        )
        await loadTask.value

        #expect(viewModel.state == .loading)
    }
}

private struct ImmediateStationsRepository: StationsRepository {
    let result: Result<[Station], StationsRepositoryError>

    func fetchStations() async throws -> [Station] {
        try result.get()
    }
}

private struct UnrelatedErrorStationsRepository: StationsRepository {
    private struct UnrelatedTestError: Error {}

    func fetchStations() async throws -> [Station] {
        throw UnrelatedTestError()
    }
}

private enum LateRepositoryCompletion: CaseIterable, Sendable {
    case success
    case failure

    func response(station: Station) -> Result<[Station], any Error> {
        switch self {
        case .success:
            .success([station])
        case .failure:
            .failure(StationsRepositoryError.unavailable)
        }
    }
}

private actor ControlledStationsRepository: StationsRepository {
    typealias Response = Result<[Station], any Error>

    private var pendingRequest: CheckedContinuation<[Station], any Error>?
    private var wasRequested = false
    private var requestWaiters: [CheckedContinuation<Void, Never>] = []
    private var wasCancelled = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    func fetchStations() async throws -> [Station] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequest = continuation
                wasRequested = true

                for waiter in requestWaiters {
                    waiter.resume()
                }
                requestWaiters.removeAll()
            }
        } onCancel: {
            Task {
                await self.recordCancellation()
            }
        }
    }

    func waitUntilRequested() async {
        guard !wasRequested else { return }

        await withCheckedContinuation { continuation in
            requestWaiters.append(continuation)
        }
    }

    func waitUntilCancelled() async {
        guard !wasCancelled else { return }

        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    func complete(with response: Response) {
        guard let pendingRequest else {
            Issue.record("No pending stations request")
            return
        }

        self.pendingRequest = nil
        pendingRequest.resume(with: response)
    }

    private func recordCancellation() {
        wasCancelled = true

        for waiter in cancellationWaiters {
            waiter.resume()
        }
        cancellationWaiters.removeAll()
    }
}
