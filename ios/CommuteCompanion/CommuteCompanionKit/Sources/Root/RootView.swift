import Foundation
import SwiftUI
import APIClient
import DeparturesFeature
import StationsFeature

public struct RootView: View {
    private let apiClient: APIClient
    private let stationsView: StationsView

    public init(baseURL: URL) {
        let apiClient = APIClient(baseURL: baseURL)

        self.apiClient = apiClient
        stationsView = StationsView(apiClient: apiClient)
    }

    public var body: some View {
        NavigationStack {
            stationsView
                .navigationDestination(for: Station.self) { station in
                    DeparturesView(
                        apiClient: apiClient,
                        stationID: station.id,
                        stationName: station.name
                    )
                }
        }
    }
}
