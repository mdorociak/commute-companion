import Foundation
import Testing
@testable import DeparturesFeature

@MainActor
@Suite
struct DeparturesViewModelTests {

    @Test
    func loadTransitionsFromIdleThroughLoadingToLoadedAndPreservesOrder() async throws {
        let laterDeparture = Departure(
            id: "later",
            line: "D1",
            destination: "Wrocław Główny",
            scheduledAt: try Date("2026-05-20T06:11:00+02:00", strategy: .iso8601),
            platform: "II"
        )
        let earlierDeparture = Departure(
            id: "earlier",
            line: "D7",
            destination: "Sędzisław",
            scheduledAt: try Date("2026-05-20T05:36:00+02:00", strategy: .iso8601),
            platform: "I"
        )
        let repository = ControlledDeparturesRepository()
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: repository,
            now: { firstCheck }
        )

        #expect(viewModel.state == .idle)

        let loadTask = Task {
            await viewModel.load()
        }

        let requestedStationID = await repository.waitUntilRequested()

        #expect(requestedStationID == "2246799")
        #expect(viewModel.state == .loading)

        await repository.complete(
            with: .success([laterDeparture, earlierDeparture])
        )
        await loadTask.value

        #expect(
            viewModel.state == .loaded(
                [laterDeparture, earlierDeparture],
                fetchedAt: firstCheck
            )
        )
    }

    @Test
    func loadMapsSuccessfulEmptyResultToEmpty() async {
        let repository = ScriptedDeparturesRepository([.success([])])
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: repository,
            now: { firstCheck }
        )

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    @Test
    func loadMapsRepositoryErrorsToViewFailures() async {
        let cases: [
            (DeparturesRepositoryError, DeparturesViewFailure)
        ] = [
            (.unreachable, .unreachable),
            (.serverFailure, .serverFailure),
            (.invalidData, .invalidData),
            (.unknownStation(.origin), .unknownStation(.origin)),
            (.unknownStation(.onward), .unknownStation(.onward)),
            (.unexpected, .unexpected),
        ]

        for (repositoryError, viewFailure) in cases {
            let repository = ScriptedDeparturesRepository([
                .failure(repositoryError)
            ])
            let viewModel = DeparturesViewModel(
                query: DepartureQuery(stationID: "2246799"),
                repository: repository,
                now: { firstCheck }
            )

            await viewModel.load()

            #expect(viewModel.state == .failure(viewFailure))
        }
    }

    @Test
    func loadMapsUnrelatedErrorToUnexpectedFailure() async {
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: UnrelatedErrorDeparturesRepository(),
            now: { firstCheck }
        )

        await viewModel.load()

        #expect(viewModel.state == .failure(.unexpected))
    }

    @Test(arguments: LateRepositoryCompletion.allCases)
    fileprivate func cancelledLoadCannotPublishLateRepositoryCompletion(
        _ lateCompletion: LateRepositoryCompletion
    ) async throws {
        let departure = Departure(
            id: "late",
            line: "D1",
            destination: "Wrocław Główny",
            scheduledAt: try Date("2026-05-20T06:11:00+02:00", strategy: .iso8601),
            platform: "II"
        )
        let repository = ControlledDeparturesRepository()
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: repository,
            now: { firstCheck }
        )

        let loadTask = Task {
            await viewModel.load()
        }
        _ = await repository.waitUntilRequested()

        loadTask.cancel()
        await repository.waitUntilCancelled()

        await repository.complete(
            with: lateCompletion.response(departure: departure)
        )
        await loadTask.value

        #expect(viewModel.state == .loading)
    }

    @Test
    func refreshKeepsShownDeparturesUntilNewerOnesArrive() async {
        let clock = TestClock(firstCheck)
        let repository = ControlledDeparturesRepository()
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: repository,
            now: { clock.now }
        )

        await load(
            viewModel,
            answering: 1,
            from: repository,
            with: .success([departure("first")])
        )

        clock.now = secondCheck
        let refreshTask = Task {
            await viewModel.load()
        }
        _ = await repository.waitUntilRequested(request: 2)

        #expect(
            viewModel.state == .loaded(
                [departure("first")],
                fetchedAt: firstCheck
            )
        )

        await repository.complete(
            request: 2,
            with: .success([departure("second")])
        )
        await refreshTask.value

        #expect(
            viewModel.state == .loaded(
                [departure("second")],
                fetchedAt: secondCheck
            )
        )
    }

    @Test
    func failedRefreshKeepsShownDeparturesWithTheirFetchTime() async {
        let cases: [
            (DeparturesRepositoryError, DeparturesViewFailure)
        ] = [
            (.unreachable, .unreachable),
            (.serverFailure, .serverFailure),
            (.invalidData, .invalidData),
            (.unexpected, .unexpected),
        ]

        for (repositoryError, viewFailure) in cases {
            let clock = TestClock(firstCheck)
            let viewModel = DeparturesViewModel(
                query: DepartureQuery(stationID: "2246799"),
                repository: ScriptedDeparturesRepository([
                    .success([departure("shown")]),
                    .failure(repositoryError),
                ]),
                now: { clock.now }
            )

            await viewModel.load()
            clock.now = secondCheck
            await viewModel.load()

            #expect(
                viewModel.state == .refreshFailed(
                    [departure("shown")],
                    fetchedAt: firstCheck,
                    viewFailure
                )
            )
        }
    }

    @Test
    func refreshThatNoLongerFindsAStationReplacesShownDepartures() async {
        for role in [DepartureStationRole.origin, .onward] {
            let viewModel = DeparturesViewModel(
                query: DepartureQuery(stationID: "2246799"),
                repository: ScriptedDeparturesRepository([
                    .success([departure("shown")]),
                    .failure(.unknownStation(role)),
                ]),
                now: { firstCheck }
            )

            await viewModel.load()
            await viewModel.load()

            #expect(viewModel.state == .failure(.unknownStation(role)))
        }
    }

    @Test
    func refreshThatFindsNoDeparturesReplacesShownDeparturesWithEmpty() async {
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: ScriptedDeparturesRepository([
                .success([departure("shown")]),
                .success([]),
            ]),
            now: { firstCheck }
        )

        await viewModel.load()
        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    @Test
    func retryAfterFailedRefreshShowsDeparturesWithoutTheFailureWhileInFlight() async {
        let clock = TestClock(firstCheck)
        let repository = ControlledDeparturesRepository()
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: repository,
            now: { clock.now }
        )

        await load(
            viewModel,
            answering: 1,
            from: repository,
            with: .success([departure("shown")])
        )
        await load(
            viewModel,
            answering: 2,
            from: repository,
            with: .failure(DeparturesRepositoryError.unreachable)
        )

        clock.now = secondCheck
        let retryTask = Task {
            await viewModel.load()
        }
        _ = await repository.waitUntilRequested(request: 3)

        #expect(
            viewModel.state == .loaded(
                [departure("shown")],
                fetchedAt: firstCheck
            )
        )

        await repository.complete(
            request: 3,
            with: .success([departure("retried")])
        )
        await retryTask.value

        #expect(
            viewModel.state == .loaded(
                [departure("retried")],
                fetchedAt: secondCheck
            )
        )
    }

    @Test(arguments: LateRepositoryCompletion.allCases)
    fileprivate func supersededLoadCannotOverwriteANewerOne(
        _ lateCompletion: LateRepositoryCompletion
    ) async {
        let repository = ControlledDeparturesRepository()
        let viewModel = DeparturesViewModel(
            query: DepartureQuery(stationID: "2246799"),
            repository: repository,
            now: { firstCheck }
        )

        let supersededTask = Task {
            await viewModel.load()
        }
        _ = await repository.waitUntilRequested(request: 1)

        let newerTask = Task {
            await viewModel.load()
        }
        _ = await repository.waitUntilRequested(request: 2)

        await repository.complete(
            request: 2,
            with: .success([departure("newer")])
        )
        await newerTask.value

        await repository.complete(
            request: 1,
            with: lateCompletion.response(departure: departure("superseded"))
        )
        await supersededTask.value

        #expect(
            viewModel.state == .loaded(
                [departure("newer")],
                fetchedAt: firstCheck
            )
        )
    }

    private func load(
        _ viewModel: DeparturesViewModel,
        answering request: Int,
        from repository: ControlledDeparturesRepository,
        with response: ControlledDeparturesRepository.Response
    ) async {
        let loadTask = Task {
            await viewModel.load()
        }
        _ = await repository.waitUntilRequested(request: request)

        await repository.complete(request: request, with: response)
        await loadTask.value
    }
}

private let firstCheck = try! Date("2026-05-20T05:00:00+02:00", strategy: .iso8601)
private let secondCheck = try! Date("2026-05-20T05:10:00+02:00", strategy: .iso8601)

private func departure(_ id: String) -> Departure {
    Departure(
        id: id,
        line: "D1",
        destination: "Wrocław Główny",
        scheduledAt: try! Date("2026-05-20T06:11:00+02:00", strategy: .iso8601),
        platform: "II"
    )
}

private final class TestClock {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

private actor ScriptedDeparturesRepository: DeparturesRepository {
    private var results: [Result<[Departure], DeparturesRepositoryError>]

    init(_ results: [Result<[Departure], DeparturesRepositoryError>]) {
        self.results = results
    }

    func fetchDepartures(query: DepartureQuery) async throws -> [Departure] {
        guard !results.isEmpty else {
            Issue.record("No scripted departure response left")
            throw DeparturesRepositoryError.unexpected
        }

        return try results.removeFirst().get()
    }
}

private struct UnrelatedErrorDeparturesRepository: DeparturesRepository {
    private struct UnrelatedTestError: Error {}

    func fetchDepartures(query: DepartureQuery) async throws -> [Departure] {
        throw UnrelatedTestError()
    }
}

private enum LateRepositoryCompletion: CaseIterable, Sendable {
    case success
    case failure

    func response(
        departure: Departure
    ) -> Result<[Departure], any Error> {
        switch self {
        case .success:
            .success([departure])
        case .failure:
            .failure(DeparturesRepositoryError.unreachable)
        }
    }
}

private actor ControlledDeparturesRepository: DeparturesRepository {
    typealias Response = Result<[Departure], any Error>

    private var pendingRequests: [
        Int: CheckedContinuation<[Departure], any Error>
    ] = [:]
    private var requestedStationIDs: [String] = []
    private var requestWaiters: [
        (request: Int, continuation: CheckedContinuation<String, Never>)
    ] = []
    private var wasCancelled = false
    private var cancellationWaiters: [
        CheckedContinuation<Void, Never>
    ] = []

    func fetchDepartures(query: DepartureQuery) async throws -> [Departure] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                requestedStationIDs.append(query.stationID)
                pendingRequests[requestedStationIDs.count] = continuation

                let arrived = requestWaiters.filter {
                    $0.request <= requestedStationIDs.count
                }
                requestWaiters.removeAll {
                    $0.request <= requestedStationIDs.count
                }
                for waiter in arrived {
                    waiter.continuation.resume(
                        returning: requestedStationIDs[waiter.request - 1]
                    )
                }
            }
        } onCancel: {
            Task {
                await self.recordCancellation()
            }
        }
    }

    func waitUntilRequested(request: Int = 1) async -> String {
        if request <= requestedStationIDs.count {
            return requestedStationIDs[request - 1]
        }

        return await withCheckedContinuation { continuation in
            requestWaiters.append((request, continuation))
        }
    }

    func waitUntilCancelled() async {
        guard !wasCancelled else { return }

        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    func complete(request: Int = 1, with response: Response) {
        guard let pendingRequest = pendingRequests.removeValue(
            forKey: request
        ) else {
            Issue.record("No pending departure request \(request)")
            return
        }

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
