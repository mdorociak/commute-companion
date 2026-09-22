import Foundation
import Testing
@testable import CommuteFeature

@MainActor
@Suite
struct CommuteSetupViewModelTests {

    @Test
    func oneChosenStationIsNotEnoughToSave() throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let viewModel = makeSetupViewModel(directory: directory)

        viewModel.select(.brzeg, as: .home)

        #expect(viewModel.canSave == false)
    }

    @Test
    func theSameStationChosenTwiceCannotBeSaved() throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let viewModel = makeSetupViewModel(directory: directory)

        viewModel.select(.brzeg, as: .home)
        viewModel.select(.brzeg, as: .destination)

        #expect(viewModel.canSave == false)
    }

    @Test
    func twoDifferentStationsCanBeSaved() throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let viewModel = makeSetupViewModel(directory: directory)

        viewModel.select(.brzeg, as: .home)
        viewModel.select(.wroclaw, as: .destination)

        #expect(viewModel.canSave)
    }

    @Test
    func savingReportsTheCommuteUpwardAndItLoadsBack() async throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let recorder = SavedCommuteRecorder()
        let store = SavedCommuteStore(directory: directory)
        let viewModel = CommuteSetupViewModel(store: store) { recorder.record($0) }

        viewModel.select(.brzeg, as: .home)
        viewModel.select(.wroclaw, as: .destination)
        await viewModel.save()

        let expected = try #require(
            SavedCommute(home: .brzeg, destination: .wroclaw)
        )
        let loaded = try await store.load()

        #expect(recorder.commute == expected)
        #expect(loaded == .configured(expected))
    }

    @Test
    func aFailedSaveKeepsBothSelections() async throws {
        let blocked = try makeTemporaryFile()
        defer { remove(blocked) }
        let viewModel = makeSetupViewModel(directory: blocked)

        viewModel.select(.brzeg, as: .home)
        viewModel.select(.wroclaw, as: .destination)
        await viewModel.save()

        #expect(viewModel.saveState == .failed)
        #expect(viewModel.home == .brzeg)
        #expect(viewModel.destination == .wroclaw)
    }

    @Test
    func aFailedSaveIsClearedByChoosingAgain() async throws {
        let blocked = try makeTemporaryFile()
        defer { remove(blocked) }
        let viewModel = makeSetupViewModel(directory: blocked)

        viewModel.select(.brzeg, as: .home)
        viewModel.select(.wroclaw, as: .destination)
        await viewModel.save()
        viewModel.select(.opole, as: .destination)

        #expect(viewModel.saveState == .idle)
    }

    @Test
    func anExistingCommuteIsTheStartingPoint() throws {
        let directory = try makeTemporaryDirectory()
        defer { remove(directory) }
        let commute = try #require(
            SavedCommute(home: .brzeg, destination: .wroclaw)
        )
        let viewModel = CommuteSetupViewModel(
            store: SavedCommuteStore(directory: directory),
            commute: commute
        ) { _ in }

        #expect(viewModel.home == .brzeg)
        #expect(viewModel.destination == .wroclaw)
        #expect(viewModel.canSave)
    }
}

@MainActor
private final class SavedCommuteRecorder {
    private(set) var commute: SavedCommute?

    func record(_ commute: SavedCommute) {
        self.commute = commute
    }
}

@MainActor
private func makeSetupViewModel(directory: URL) -> CommuteSetupViewModel {
    CommuteSetupViewModel(store: SavedCommuteStore(directory: directory)) { _ in }
}
