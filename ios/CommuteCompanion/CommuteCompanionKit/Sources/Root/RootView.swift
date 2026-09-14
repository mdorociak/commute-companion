import Foundation
import SwiftUI
import APIClient
import CommuteFeature
import DeparturesFeature
import StationsFeature

public struct RootView: View {
    private let apiClient: APIClient
    private let stationsView: StationsView

    @State private var savedCommute: SavedCommuteViewModel

    public init(baseURL: URL, commuteDirectory: URL) {
        let apiClient = APIClient(baseURL: baseURL)

        self.apiClient = apiClient
        stationsView = StationsView(apiClient: apiClient)
        _savedCommute = State(
            initialValue: SavedCommuteViewModel(
                store: SavedCommuteStore(directory: commuteDirectory)
            )
        )
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
        switch savedCommute.state {
        case .idle, .loading:
            ProgressView("Loading your commute…")

        case .notConfigured, .configured:
            stationsView

        case .failure(let failure):
            SavedCommuteFailureView(failure: failure)
        }
    }
}
