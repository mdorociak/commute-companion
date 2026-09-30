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
    @State private var reloadTrigger = false
    @State private var setupRequest: SetupRequest?

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
        .task(id: reloadTrigger) {
            await savedCommute.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch RootDestination(savedCommute.state) {
        case .loading:
            ProgressView("Loading your commute…")

        case .configured(let commute):
            board(for: commute)

        case .setup(let reason):
            setupScreen(reason: reason)
                .toolbar { browseStations }

        case .unreadable:
            SavedCommuteUnreadableView { reloadTrigger.toggle() }
                .toolbar { browseStations }
        }
    }

    @ToolbarContentBuilder
    private var browseStations: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                stationsView
            } label: {
                Label("Stations", systemImage: "list.bullet")
            }
        }
    }

    private func board(for commute: SavedCommute) -> some View {
        let route = DepartureRoute(commute)

        return CommuteBoardView(
            apiClient: apiClient,
            route: route,
            stationNoLongerResolves: { stationID in
                setupRequest = SetupRequest(
                    reason: commute.field(forStationID: stationID)
                        .map(CommuteSetupReason.stationNoLongerResolves)
                )
            }
        )
        .id(route)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    setupRequest = SetupRequest(reason: nil)
                } label: {
                    Label("Edit commute", systemImage: "slider.horizontal.3")
                }
            }

            browseStations
        }
        .sheet(item: $setupRequest) { request in
            NavigationStack {
                setupScreen(commute: commute, reason: request.reason)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                setupRequest = nil
                            }
                        }
                    }
            }
        }
    }

    private func setupScreen(
        commute: SavedCommute? = nil,
        reason: CommuteSetupReason?
    ) -> some View {
        let model = savedCommute

        return CommuteSetupView(
            store: store,
            commute: commute,
            reason: reason,
            saved: { newCommute in
                model.commuteSaved(newCommute)
                setupRequest = nil
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

private struct SetupRequest: Identifiable {
    let id = UUID()
    let reason: CommuteSetupReason?
}
