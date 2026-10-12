import Foundation
import SwiftUI
import APIClient

public struct DeparturesView: View {
    private let stationName: String

    @State private var viewModel: DeparturesViewModel
    @State private var reloadTrigger = false

    @Environment(\.scenePhase) private var scenePhase

    public init(
        apiClient: APIClient,
        stationID: String,
        stationName: String
    ) {
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        self.stationName = stationName
        _viewModel = State(
            initialValue: DeparturesViewModel(
                query: DepartureQuery(stationID: stationID),
                repository: repository,
                now: { Date.now }
            )
        )
    }

    public var body: some View {
        DeparturesContent(
            originName: stationName,
            destinationName: nil,
            state: viewModel.state,
            chooseAgain: nil,
            retry: { reloadTrigger.toggle() }
        )
        .navigationTitle(stationName)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: reloadTrigger) {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                reloadTrigger.toggle()
            }
        }
    }
}
