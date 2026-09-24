import SwiftUI

public struct CommuteSetupView<Picker: View>: View {
    @State private var viewModel: CommuteSetupViewModel

    private let picker: (@escaping (StationReference) -> Void) -> Picker

    public init(
        store: SavedCommuteStore,
        commute: SavedCommute? = nil,
        reason: CommuteSetupReason? = nil,
        saved: @escaping (SavedCommute) -> Void,
        @ViewBuilder picker: @escaping (@escaping (StationReference) -> Void) -> Picker
    ) {
        _viewModel = State(
            initialValue: CommuteSetupViewModel(
                store: store,
                commute: commute,
                reason: reason,
                saved: saved
            )
        )
        self.picker = picker
    }

    init(
        viewModel: CommuteSetupViewModel,
        @ViewBuilder picker: @escaping (@escaping (StationReference) -> Void) -> Picker
    ) {
        _viewModel = State(initialValue: viewModel)
        self.picker = picker
    }

    public var body: some View {
        Form {
            if let reason = viewModel.reason {
                Section {
                    Label {
                        Text(reason.message)
                    } icon: {
                        Image(systemName: reason.systemImage)
                    }
                }
            }

            Section {
                stationRow(.home, station: viewModel.home)
                stationRow(.destination, station: viewModel.destination)
            } header: {
                Text("Stations")
            } footer: {
                Text("The daily board shows departures from your home station towards your destination.")
            }

            if viewModel.saveState == .failed {
                Section {
                    Label {
                        Text("Your commute could not be saved. Try again.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
            }

            Section {
                Button("Save") {
                    Task { await viewModel.save() }
                }
                .disabled(!viewModel.canSave)
            }
        }
        .navigationTitle("Your commute")
    }

    private func stationRow(
        _ field: CommuteField,
        station: StationReference?
    ) -> some View {
        NavigationLink {
            PickerHost(picker: picker) { chosen in
                viewModel.select(chosen, as: field)
            }
        } label: {
            LabeledContent {
                value(for: station)
            } label: {
                Text(field.title)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func value(for station: StationReference?) -> some View {
        if let station {
            Text(verbatim: station.displayName)
        } else {
            Text("Not set")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PickerHost<Picker: View>: View {
    @Environment(\.dismiss) private var dismiss

    let picker: (@escaping (StationReference) -> Void) -> Picker
    let select: (StationReference) -> Void

    var body: some View {
        picker { station in
            select(station)
            dismiss()
        }
    }
}

private extension CommuteField {
    var title: LocalizedStringResource {
        switch self {
        case .home:
            "Home"

        case .destination:
            "Destination"
        }
    }
}

private extension CommuteSetupReason {
    var message: LocalizedStringResource {
        switch self {
        case .storedCommuteUnusable:
            "Your saved commute could not be read. Choose your stations again to replace it."

        case .stationNoLongerResolves(.home):
            "Your home station is no longer in the timetable. Choose it again."

        case .stationNoLongerResolves(.destination):
            "Your destination is no longer in the timetable. Choose it again."
        }
    }

    var systemImage: String {
        switch self {
        case .storedCommuteUnusable:
            "exclamationmark.triangle"

        case .stationNoLongerResolves:
            "mappin.slash"
        }
    }
}

private struct PreviewStationPicker: View {
    let select: (StationReference) -> Void

    var body: some View {
        List(previewStations, id: \.stationID) { station in
            Button {
                select(station)
            } label: {
                Text(verbatim: station.displayName)
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Choose a station")
    }
}

private struct CommuteSetupPreview: View {
    @State private var viewModel: CommuteSetupViewModel

    private let failsToSave: Bool

    init(
        commute: SavedCommute? = nil,
        reason: CommuteSetupReason? = nil,
        failsToSave: Bool = false
    ) {
        self.failsToSave = failsToSave
        _viewModel = State(
            initialValue: CommuteSetupViewModel(
                store: SavedCommuteStore(
                    directory: URL(filePath: "/dev/null/commute-setup-preview")
                ),
                commute: commute,
                reason: reason
            ) { _ in }
        )
    }

    var body: some View {
        NavigationStack {
            CommuteSetupView(viewModel: viewModel) { select in
                PreviewStationPicker(select: select)
            }
        }
        .task {
            if failsToSave {
                await viewModel.save()
            }
        }
    }
}

private let previewStations = [
    StationReference(stationID: "brzeg", displayName: "Brzeg"),
    StationReference(stationID: "wroclaw", displayName: "Wrocław Główny"),
    StationReference(stationID: "opole", displayName: "Opole Główne"),
]

private let previewCommute = SavedCommute(
    home: StationReference(stationID: "brzeg", displayName: "Brzeg"),
    destination: StationReference(stationID: "wroclaw", displayName: "Wrocław Główny")
)

#Preview("First run") {
    CommuteSetupPreview()
}

#Preview("Configured") {
    CommuteSetupPreview(commute: previewCommute)
}

#Preview("Configured – Accessibility text") {
    CommuteSetupPreview(commute: previewCommute)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Save failed") {
    CommuteSetupPreview(commute: previewCommute, failsToSave: true)
}

#Preview("Stored commute unusable") {
    CommuteSetupPreview(reason: .storedCommuteUnusable)
}

#Preview("Home station gone") {
    CommuteSetupPreview(
        commute: previewCommute,
        reason: .stationNoLongerResolves(.home)
    )
}
