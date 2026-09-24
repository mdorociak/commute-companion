import Foundation
import SwiftUI
import APIClient
import CommuteFeature
import DeparturesFeature
import StationsFeature

public struct RootView: View {
    private let apiClient: APIClient
    private let store: SavedCommuteStore
    private let stationsView: StationsView

    @State private var savedCommute: SavedCommuteViewModel

    public init(baseURL: URL, commuteDirectory: URL) {
        let apiClient = APIClient(baseURL: baseURL)
        let store = SavedCommuteStore(directory: commuteDirectory)

        self.apiClient = apiClient
        self.store = store
        stationsView = StationsView(apiClient: apiClient)
        _savedCommute = State(initialValue: SavedCommuteViewModel(store: store))
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationDestination(for: Station.self) { station in
                    DeparturesView(
                        apiClient: apiClient,
                        stationID: station.id,
                        stationName: station.name
                    )
                }
        }
        .task {
            await savedCommute.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch RootDestination(savedCommute.state) {
        case .loading:
            ProgressView("Loading your commute…")

        case .configured:
            stationsView

        case .setup(let reason):
            setupScreen(reason: reason)

        case .unreadable:
            SavedCommuteFailureView(failure: .unreadable)
        }
    }

    private func setupScreen(reason: CommuteSetupReason?) -> some View {
        let model = savedCommute

        return CommuteSetupView(
            store: store,
            reason: reason,
            saved: { commute in
                model.commuteSaved(commute)
            }
        ) { select in
            StationPickerView(apiClient: apiClient) { station in
                select(
                    StationReference(
                        stationID: station.id,
                        displayName: station.name
                    )
                )
            }
        }
    }
}
