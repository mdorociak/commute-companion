import SwiftUI
import APIClient

public struct StationsView: View {
    @State private var viewModel: StationsViewModel
    @State private var reloadTrigger = false

    public init(apiClient: APIClient) {
        let repository = RemoteStationsRepository(apiClient: apiClient)
        _viewModel = State(initialValue: StationsViewModel(repository: repository))
    }

    init(viewModel: StationsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        StationsContent(
            state: viewModel.state,
            filteredStations: viewModel.filteredStations,
            hasActiveSearch: viewModel.hasActiveSearch,
            rowAction: .navigate,
            retry: { reloadTrigger.toggle() }
        )
        .navigationTitle("Stations")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $viewModel.searchText, prompt: "Search stations")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .task(id: reloadTrigger) {
            await viewModel.load()
        }
    }
}
