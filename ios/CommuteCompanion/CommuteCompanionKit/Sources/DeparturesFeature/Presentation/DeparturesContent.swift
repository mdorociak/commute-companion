import Foundation
import SwiftUI

struct DeparturesContent: View {
    let originName: String
    let destinationName: String?
    let state: DeparturesViewState
    let chooseAgain: ((DepartureStationRole) -> Void)?
    let retry: () -> Void

    @Environment(\.locale) private var locale

    @ViewBuilder
    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading scheduled departures…")

        case .loaded(let departures, let fetchedAt):
            departuresList(departures, fetchedAt: fetchedAt)

        case .refreshFailed(let departures, let fetchedAt, let failure):
            departuresList(
                departures,
                fetchedAt: fetchedAt,
                refreshFailure: failure
            )

        case .empty:
            ContentUnavailableView(
                "No scheduled departures",
                systemImage: "clock.badge.xmark",
                description: Text(emptyDescription)
            )

        case .failure(let failure):
            failureView(for: failure)
        }
    }

    private var emptyDescription: LocalizedStringResource {
        if let destinationName {
            "No upcoming scheduled departures from \(originName) towards \(destinationName)."
        } else {
            "No upcoming scheduled departures from \(originName)."
        }
    }

    private func departuresList(
        _ departures: [Departure],
        fetchedAt: Date,
        refreshFailure: DeparturesViewFailure? = nil
    ) -> some View {
        let fetchedTime = fetchedAt.formatted(.warsawTime(locale: locale))

        return List {
            if let refreshFailure {
                Section {
                    RefreshFailureNotice(
                        failure: refreshFailure,
                        fetchedTime: fetchedTime,
                        retry: retry
                    )
                }
            }

            Section {
                ForEach(departures) { departure in
                    DepartureRow(departure: departure)
                }
            } header: {
                Text("Scheduled departures")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Showing the next ^[\(departures.count) scheduled departure](inflect: true) in Warsaw time. Later services may not be listed, and realtime updates are not available yet."
                    )

                    Text("Last checked at \(fetchedTime).")
                }
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
            if case .unknownStation(let role) = failure, let chooseAgain {
                Button("Choose again") {
                    chooseAgain(role)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct RefreshFailureNotice: View {
    let failure: DeparturesViewFailure
    let fetchedTime: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Could not refresh")
                        .font(.headline)

                    Text(failure.message)

                    Text("Showing departures as of \(fetchedTime).")
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: failure.systemImage)
            }
            .accessibilityElement(children: .combine)

            Button("Try again", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}

private struct DepartureRow: View {
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
        departure.scheduledAt.formatted(.warsawTime(locale: locale))
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

private extension FormatStyle where Self == Date.FormatStyle {
    static func warsawTime(locale: Locale) -> Self {
        Date.FormatStyle(
            date: .omitted,
            time: .shortened,
            locale: locale,
            calendar: Calendar(identifier: .gregorian),
            timeZone: warsawTimeZone
        )
    }
}

private let warsawTimeZone: TimeZone = {
    guard let timeZone = TimeZone(identifier: "Europe/Warsaw") else {
        preconditionFailure("Europe/Warsaw must be a valid time zone")
    }

    return timeZone
}()

private extension DeparturesViewFailure {
    var title: LocalizedStringResource {
        switch self {
        case .unreachable, .serverFailure:
            "Scheduled departures unavailable"
        case .invalidData:
            "Unable to read scheduled departures"
        case .unknownStation:
            "Not in the current timetable"
        case .unexpected:
            "Unable to load scheduled departures"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .unreachable:
            "The server could not be reached. Check your connection and try again."
        case .serverFailure:
            "The server could not provide scheduled departures right now. Try again later."
        case .invalidData:
            "The server response could not be understood. Try again later."
        case .unknownStation(.origin):
            "This station is not served by the current timetable."
        case .unknownStation(.onward):
            "The station you are heading towards is not in the current timetable."
        case .unexpected:
            "An unexpected error occurred. Try again."
        }
    }

    var systemImage: String {
        switch self {
        case .unreachable:
            "wifi.slash"
        case .serverFailure:
            "exclamationmark.icloud"
        case .invalidData:
            "exclamationmark.triangle"
        case .unknownStation:
            "mappin.slash"
        case .unexpected:
            "exclamationmark.circle"
        }
    }
}

private struct DeparturesStatePreview: View {
    let state: DeparturesViewState
    var destinationName: String? = nil
    var chooseAgain: ((DepartureStationRole) -> Void)? = nil
    var title = "Brzeg"

    var body: some View {
        NavigationStack {
            DeparturesContent(
                originName: "Brzeg",
                destinationName: destinationName,
                state: state,
                chooseAgain: chooseAgain,
                retry: {}
            )
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private let previewFetchedAt = Date(timeIntervalSince1970: 1_779_247_000)

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
        ], fetchedAt: previewFetchedAt)
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
        ], fetchedAt: previewFetchedAt)
    )
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Empty") {
    DeparturesStatePreview(state: .empty)
}

#Preview("Unreachable") {
    DeparturesStatePreview(state: .failure(.unreachable))
}

#Preview("Server failure") {
    DeparturesStatePreview(state: .failure(.serverFailure))
}

#Preview("Invalid data") {
    DeparturesStatePreview(state: .failure(.invalidData))
}

#Preview("Unknown station") {
    DeparturesStatePreview(state: .failure(.unknownStation(.origin)))
}

#Preview("Unexpected failure") {
    DeparturesStatePreview(state: .failure(.unexpected))
}

#Preview("Board – loaded") {
    DeparturesStatePreview(
        state: .loaded([
            Departure(
                id: "board-brzeg-wroclaw",
                line: "D1",
                destination: "Wrocław Główny",
                scheduledAt: Date(timeIntervalSince1970: 1_779_248_160),
                platform: "II"
            ),
        ], fetchedAt: previewFetchedAt),
        destinationName: "Wrocław Główny",
        title: "Brzeg → Wrocław Główny"
    )
}

#Preview("Board – refresh failed") {
    DeparturesStatePreview(
        state: .refreshFailed(
            [
                Departure(
                    id: "board-refresh-failed",
                    line: "D1",
                    destination: "Wrocław Główny",
                    scheduledAt: Date(timeIntervalSince1970: 1_779_248_160),
                    platform: "II"
                ),
            ],
            fetchedAt: previewFetchedAt,
            .unreachable
        ),
        destinationName: "Wrocław Główny",
        title: "Brzeg → Wrocław Główny"
    )
}

#Preview("Board – empty") {
    DeparturesStatePreview(
        state: .empty,
        destinationName: "Wrocław Główny",
        title: "Brzeg → Wrocław Główny"
    )
}

#Preview("Board – onward station gone") {
    DeparturesStatePreview(
        state: .failure(.unknownStation(.onward)),
        destinationName: "Wrocław Główny",
        chooseAgain: { _ in },
        title: "Brzeg → Wrocław Główny"
    )
}
