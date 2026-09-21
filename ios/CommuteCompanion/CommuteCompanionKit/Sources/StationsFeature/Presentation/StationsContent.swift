import SwiftUI

enum StationRowAction {
    case navigate
    case select((Station) -> Void)
}

struct StationsContent: View {
    let state: StationsViewState
    let filteredStations: [Station]
    let hasActiveSearch: Bool
    let rowAction: StationRowAction
    let retry: () -> Void

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading stations…")

        case .loaded:
            if filteredStations.isEmpty,
               hasActiveSearch {
                noMatchingStationsView
            } else {
                stationsList(filteredStations)
            }

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

    private var noMatchingStationsView: some View {
        ContentUnavailableView(
            "No matching stations",
            systemImage: "xmark.circle.fill",
            description: Text(
                "No stations match your search query."
            )
        )
    }

    private func stationsList(_ stations: [Station]) -> some View {
        List(stations) { station in
            row(for: station)
        }
    }

    @ViewBuilder
    private func row(for station: Station) -> some View {
        switch rowAction {
        case .navigate:
            NavigationLink(value: station) {
                label(for: station)
            }

        case .select(let select):
            Button {
                select(station)
            } label: {
                label(for: station)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func label(for station: Station) -> some View {
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

    private func failureView(for failure: StationsViewFailure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: failure.systemImage)
        } description: {
            Text(failure.message)
        } actions: {
            Button("Retry", action: retry)
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

private struct StationsStatePreview: View {
    let state: StationsViewState
    var filteredStations: [Station] = []
    var hasActiveSearch = false
    var rowAction: StationRowAction = .navigate
    var title: LocalizedStringResource = "Stations"

    var body: some View {
        NavigationStack {
            StationsContent(
                state: state,
                filteredStations: filteredStations,
                hasActiveSearch: hasActiveSearch,
                rowAction: rowAction,
                retry: {}
            )
            .navigationTitle(Text(title))
        }
    }
}

private let previewStations = [
    Station(id: "2246799", name: "Brzeg", code: "11"),
    Station(id: "1413092", name: "Brzeg Dolny", code: "12"),
    Station(id: "wroclaw", name: "Wrocław Główny", code: nil),
]

#Preview("Loading") {
    StationsStatePreview(state: .loading)
}

#Preview("Loaded") {
    StationsStatePreview(
        state: .loaded(previewStations),
        filteredStations: previewStations
    )
}

#Preview("Loaded – Accessibility text") {
    StationsStatePreview(
        state: .loaded(previewStations),
        filteredStations: previewStations
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Selecting") {
    StationsStatePreview(
        state: .loaded(previewStations),
        filteredStations: previewStations,
        rowAction: .select { _ in },
        title: "Choose a station"
    )
}

#Preview("Selecting – Accessibility text") {
    StationsStatePreview(
        state: .loaded(previewStations),
        filteredStations: previewStations,
        rowAction: .select { _ in },
        title: "Choose a station"
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("No matching stations") {
    StationsStatePreview(
        state: .loaded(previewStations),
        filteredStations: [],
        hasActiveSearch: true
    )
}

#Preview("Empty") {
    StationsStatePreview(state: .empty)
}

#Preview("Unavailable") {
    StationsStatePreview(state: .failure(.unavailable))
}

#Preview("Invalid data") {
    StationsStatePreview(state: .failure(.invalidData))
}

#Preview("Unexpected failure") {
    StationsStatePreview(state: .failure(.unexpected))
}
