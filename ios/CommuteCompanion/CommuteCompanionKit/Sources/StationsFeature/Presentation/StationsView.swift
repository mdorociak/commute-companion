import SwiftUI
import APIClient

public struct StationsView: View {
    @State private var viewModel: StationsViewModel

    @State private var reloadTrigger = false

    public init(apiClient: APIClient) {
        let repository = RemoteStationsRepository(apiClient: apiClient)
        _viewModel = State(
            initialValue: StationsViewModel(repository: repository)
        )
    }

    init(viewModel: StationsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        ZStack {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Stations")
        .task(id: reloadTrigger) {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView("Loading stations…")

        case .loaded(let stations):
            stationsList(stations)

        case .empty:
            ContentUnavailableView(
                "No stations available",
                systemImage: "train.side.front.car",
                description: Text(
                    "The server did not return any stations."
                )
            )

        case .failure(let failure):
            failureView(for: failure)
        }
    }

    private func stationsList(_ stations: [Station]) -> some View {
        List(stations) { station in
            VStack(alignment: .leading, spacing: 4) {
                Text(station.name)

                if let code = station.code, !code.isEmpty {
                    Text("Code: \(code)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func failureView(
        for failure: StationsViewFailure
    ) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: failure.systemImage)
        } description: {
            Text(failure.message)
        } actions: {
            Button("Retry") {
                reloadTrigger.toggle()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private extension StationsViewFailure {
    var title: LocalizedStringResource {
        switch self {
        case .unavailable:
            "Stations unavailable"
        case .invalidData:
            "Unable to read station data"
        case .unexpected:
            "Something went wrong"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .unavailable:
            "Check your connection and try again."
        case .invalidData:
            "The server response could not be understood. Try again later."
        case .unexpected:
            "An unexpected error occurred. Try again."
        }
    }

    var systemImage: String {
        switch self {
        case .unavailable:
            "wifi.slash"
        case .invalidData:
            "exclamationmark.triangle"
        case .unexpected:
            "exclamationmark.circle"
        }
    }
}
