import SwiftUI
import APIClient

public struct CommuteBoardView: View {
    private let route: DepartureRoute
    private let reverse: () -> Void
    private let stationNoLongerResolves: (String) -> Void

    @State private var viewModel: DeparturesViewModel
    @State private var reloadTrigger = false

    public init(
        apiClient: APIClient,
        route: DepartureRoute,
        reverse: @escaping () -> Void,
        stationNoLongerResolves: @escaping (String) -> Void
    ) {
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        self.route = route
        self.reverse = reverse
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
        .navigationTitle("Commute")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button(action: reverse) {
                    HStack(spacing: 6) {
                        Text(verbatim: title)
                            .font(.headline)
                            .lineLimit(1)

                        Image(systemName: "arrow.left.arrow.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text("From \(route.origin.name) towards \(route.destination.name)")
                )
                .accessibilityHint("Reverses the direction")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: reloadTrigger) {
            await viewModel.load()
        }
    }

    private var title: String {
        "\(route.origin.name) → \(route.destination.name)"
    }
}
