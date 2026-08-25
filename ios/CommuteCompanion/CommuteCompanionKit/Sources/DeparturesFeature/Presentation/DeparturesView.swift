import Foundation
import SwiftUI
import APIClient

public struct DeparturesView: View {
    private let stationName: String

    @State private var viewModel: DeparturesViewModel
    @State private var reloadTrigger = false

    public init(
        apiClient: APIClient,
        stationID: String,
        stationName: String
    ) {
        let repository = RemoteDeparturesRepository(apiClient: apiClient)

        self.stationName = stationName
        _viewModel = State(
            initialValue: DeparturesViewModel(
                stationID: stationID,
                repository: repository
            )
        )
    }

    init(
        stationName: String,
        viewModel: DeparturesViewModel
    ) {
        self.stationName = stationName
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        DeparturesContent(
            stationName: stationName,
            state: viewModel.state,
            retry: { reloadTrigger.toggle() }
        )
        .navigationTitle(stationName)
        .navigationBarTitleDisplayMode(.inline)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: reloadTrigger) {
            await viewModel.load()
        }
    }
}

private struct DeparturesContent: View {
    let stationName: String
    let state: DeparturesViewState
    let retry: () -> Void

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading scheduled departures…")

        case .loaded(let departures):
            departuresList(departures)

        case .empty:
            ContentUnavailableView(
                "No scheduled departures",
                systemImage: "clock.badge.xmark",
                description: Text(
                    "No departures are scheduled from \(stationName) within the next 24 hours."
                )
            )

        case .failure(let failure):
            failureView(for: failure)
        }
    }

    private func departuresList(_ departures: [Departure]) -> some View {
        List {
            Section {
                ForEach(departures) { departure in
                    DepartureRow(departure: departure)
                }
            } header: {
                Text("Scheduled departures")
            } footer: {
                Text(
                    "Times are scheduled and shown in Warsaw time. Realtime updates are not available yet."
                )
            }
        }
    }

    private func failureView(
        for failure: DeparturesViewFailure
    ) -> some View {
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

private struct DepartureRow: View {
    private static let warsawTimeZone: TimeZone = {
        guard let timeZone = TimeZone(identifier: "Europe/Warsaw") else {
            preconditionFailure("Europe/Warsaw must be a valid time zone")
        }

        return timeZone
    }()

    let departure: Departure

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    var body: some View {
        rowLayout {
            Text(scheduledTime)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .accessibilityLabel("Scheduled time \(scheduledTime)")

            VStack(alignment: .leading, spacing: 4) {
                Text("Line \(departure.line)")
                    .font(.headline)

                if let destination {
                    Text(destination)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Destination unavailable")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let platform {
                    Label(
                        "Platform \(platform)",
                        systemImage: "signpost.right"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var rowLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        } else {
            AnyLayout(
                HStackLayout(
                    alignment: .firstTextBaseline,
                    spacing: 16
                )
            )
        }
    }

    private var scheduledTime: String {
        departure.scheduledAt.formatted(scheduledTimeFormat)
    }

    private var scheduledTimeFormat: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: Self.warsawTimeZone
        )
    }

    private var destination: String? {
        nonEmptyText(departure.destination)
    }

    private var platform: String? {
        nonEmptyText(departure.platform)
    }

    private func nonEmptyText(_ text: String?) -> String? {
        guard let text else { return nil }

        let trimmedText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return trimmedText.isEmpty ? nil : trimmedText
    }
}

private extension DeparturesViewFailure {
    var title: LocalizedStringResource {
        switch self {
        case .unavailable:
            "Scheduled departures unavailable"
        case .invalidData:
            "Unable to read scheduled departures"
        case .unexpected:
            "Unable to load scheduled departures"
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

private struct DeparturesStatePreview: View {
    let state: DeparturesViewState

    var body: some View {
        NavigationStack {
            DeparturesContent(
                stationName: "Brzeg",
                state: state,
                retry: {}
            )
            .navigationTitle("Brzeg")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Loading") {
    DeparturesStatePreview(state: .loading)
}

#Preview("Loaded") {
    DeparturesStatePreview(
        state: .loaded([
            Departure(
                id: "brzeg-wroclaw",
                line: "D1",
                destination: "Wrocław Główny",
                scheduledAt: Date(timeIntervalSince1970: 1_779_248_160),
                platform: "II"
            ),
            Departure(
                id: "brzeg-opole",
                line: "D7",
                destination: "Opole Główne",
                scheduledAt: Date(timeIntervalSince1970: 1_779_250_260),
                platform: nil
            ),
            Departure(
                id: "destination-unavailable",
                line: "D11",
                destination: nil,
                scheduledAt: Date(timeIntervalSince1970: 1_779_253_260),
                platform: "I"
            ),
        ])
    )
}

#Preview("Loaded – Accessibility text") {
    DeparturesStatePreview(
        state: .loaded([
            Departure(
                id: "brzeg-wroclaw-accessibility",
                line: "D1",
                destination: "Wrocław Główny",
                scheduledAt: Date(timeIntervalSince1970: 1_779_248_160),
                platform: "II"
            ),
            Departure(
                id: "destination-unavailable-accessibility",
                line: "D11",
                destination: nil,
                scheduledAt: Date(timeIntervalSince1970: 1_779_253_260),
                platform: nil
            ),
        ])
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Empty") {
    DeparturesStatePreview(state: .empty)
}

#Preview("Unavailable") {
    DeparturesStatePreview(state: .failure(.unavailable))
}

#Preview("Invalid data") {
    DeparturesStatePreview(state: .failure(.invalidData))
}

#Preview("Unexpected failure") {
    DeparturesStatePreview(state: .failure(.unexpected))
}
