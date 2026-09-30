import SwiftUI
import APIClient

public struct CommuteBoardView: View {
    private let route: DepartureRoute
    private let stationNoLongerResolves: (String) -> Void

    @State private var viewModel: DeparturesViewModel
    @State private var reloadTrigger = false

    public init(
        apiClient: APIClient,
        route: DepartureRoute,
        stationNoLongerResolves: @escaping (String) -> Void
    ) {
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        self.route = route
        self.stationNoLongerResolves = stationNoLongerResolves
        _viewModel = State(
            initialValue: DeparturesViewModel(
                query: DepartureQuery(route),
                repository: repository
            )
        )
    }

    public var body: some View {
        DeparturesContent(
            originName: route.origin.name,
            destinationName: route.destination.name,
            state: viewModel.state,
            chooseAgain: { role in
                stationNoLongerResolves(route.station(for: role).id)
            },
            retry: { reloadTrigger.toggle() }
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: reloadTrigger) {
            await viewModel.load()
        }
    }

    private var title: String {
        "\(route.origin.name) → \(route.destination.name)"
    }
}
