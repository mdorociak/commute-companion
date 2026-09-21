import SwiftUI
import APIClient

public struct StationPickerView: View {
    private let select: (Station) -> Void

    @State private var viewModel: StationsViewModel
    @State private var reloadTrigger = false

    public init(apiClient: APIClient, select: @escaping (Station) -> Void) {
        let repository = RemoteStationsRepository(apiClient: apiClient)

        self.select = select
        _viewModel = State(initialValue: StationsViewModel(repository: repository))
    }

    init(viewModel: StationsViewModel, select: @escaping (Station) -> Void) {
        self.select = select
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        StationsContent(
            state: viewModel.state,
            filteredStations: viewModel.filteredStations,
            hasActiveSearch: viewModel.hasActiveSearch,
            rowAction: .select(select),
            retry: { reloadTrigger.toggle() }
        )
        .navigationTitle("Choose a station")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .searchable(text: $viewModel.searchText, prompt: "Search stations")
        .task(id: reloadTrigger) {
            await viewModel.load()
        }
    }
}
