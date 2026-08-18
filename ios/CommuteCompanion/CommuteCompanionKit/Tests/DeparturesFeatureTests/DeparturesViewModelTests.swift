import Foundation
import Testing
@testable import DeparturesFeature

@MainActor
@Suite
struct DeparturesViewModelTests {

    @Test
    func loadTransitionsFromIdleThroughLoadingToLoadedAndPreservesOrder() async {
        let laterDeparture = Departure(
            id: "later",
            line: "D1",
            destination: "Wrocław Główny",
            scheduledAt: Date(timeIntervalSince1970: 1_779_250_260),
            platform: "II"
        )
        let earlierDeparture = Departure(
            id: "earlier",
            line: "D7",
            destination: "Sędzisław",
            scheduledAt: Date(timeIntervalSince1970: 1_779_248_160),
            platform: "I"
        )
        let repository = ControlledDeparturesRepository()
        let viewModel = DeparturesViewModel(
            stationID: "2246799",
            repository: repository
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
            viewModel.state == .loaded([
                laterDeparture,
                earlierDeparture,
            ])
        )
    }

    @Test
    func loadMapsSuccessfulEmptyResultToEmpty() async {
        let repository = ImmediateDeparturesRepository(
            result: .success([])
        )
        let viewModel = DeparturesViewModel(
            stationID: "2246799",
            repository: repository
        )

        await viewModel.load()

        #expect(viewModel.state == .empty)
    }

    @Test
    func loadMapsRepositoryErrorsToViewFailures() async {
        let cases: [
            (DeparturesRepositoryError, DeparturesViewFailure)
        ] = [
            (.unavailable, .unavailable),
            (.invalidData, .invalidData),
            (.unexpected, .unexpected),
        ]

        for (repositoryError, viewFailure) in cases {
            let repository = ImmediateDeparturesRepository(
                result: .failure(repositoryError)
            )
            let viewModel = DeparturesViewModel(
                stationID: "2246799",
                repository: repository
            )

            await viewModel.load()

            #expect(viewModel.state == .failure(viewFailure))
        }
    }

    @Test
    func loadMapsUnrelatedErrorToUnexpectedFailure() async {
        let viewModel = DeparturesViewModel(
            stationID: "2246799",
            repository: UnrelatedErrorDeparturesRepository()
        )

        await viewModel.load()

        #expect(viewModel.state == .failure(.unexpected))
    }

    @Test(arguments: LateRepositoryCompletion.allCases)
    fileprivate func cancelledLoadCannotPublishLateRepositoryCompletion(
        _ lateCompletion: LateRepositoryCompletion
    ) async {
        let departure = Departure(
            id: "late",
            line: "D1",
            destination: "Wrocław Główny",
            scheduledAt: Date(timeIntervalSince1970: 1_779_250_260),
            platform: "II"
        )
        let repository = ControlledDeparturesRepository()
        let viewModel = DeparturesViewModel(
            stationID: "2246799",
            repository: repository
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
}

private struct ImmediateDeparturesRepository: DeparturesRepository {
    let result: Result<[Departure], DeparturesRepositoryError>

    func fetchDepartures(stationID: String) async throws -> [Departure] {
        try result.get()
    }
}

private struct UnrelatedErrorDeparturesRepository: DeparturesRepository {
    private struct UnrelatedTestError: Error {}

    func fetchDepartures(stationID: String) async throws -> [Departure] {
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
            .failure(DeparturesRepositoryError.unavailable)
        }
    }
}

private actor ControlledDeparturesRepository: DeparturesRepository {
    typealias Response = Result<[Departure], any Error>

    private var pendingRequest: CheckedContinuation<
        [Departure],
        any Error
    >?
    private var requestedStationID: String?
    private var requestWaiters: [
        CheckedContinuation<String, Never>
    ] = []
    private var wasCancelled = false
    private var cancellationWaiters: [
        CheckedContinuation<Void, Never>
    ] = []

    func fetchDepartures(stationID: String) async throws -> [Departure] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pendingRequest = continuation
                requestedStationID = stationID

                for waiter in requestWaiters {
                    waiter.resume(returning: stationID)
                }
                requestWaiters.removeAll()
            }
        } onCancel: {
            Task {
                await self.recordCancellation()
            }
        }
    }

    func waitUntilRequested() async -> String {
        if let requestedStationID {
            return requestedStationID
        }

        return await withCheckedContinuation { continuation in
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
            Issue.record("No pending departure request")
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
