import SwiftUI

public struct SavedCommuteFailureView: View {
    private let failure: SavedCommuteFailure

    public init(failure: SavedCommuteFailure) {
        self.failure = failure
    }

    public var body: some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: failure.systemImage)
        } description: {
            Text(failure.message)
        }
    }
}

private extension SavedCommuteFailure {
    var title: LocalizedStringResource {
        switch self {
        case .unusable:
            "Saved commute unusable"

        case .unreadable:
            "Saved commute unavailable"

        case .unexpected:
            "Something went wrong"
        }
    }

    var message: LocalizedStringResource {
        switch self {
        case .unusable:
            "Your saved commute could not be read and has to be set up again."

        case .unreadable:
            "Your saved commute could not be opened. Reopen the app to try again."

        case .unexpected:
            "An unexpected error occurred while reading your saved commute."
        }
    }

    var systemImage: String {
        switch self {
        case .unusable:
            "exclamationmark.triangle"

        case .unreadable:
            "externaldrive.badge.exclamationmark"

        case .unexpected:
            "exclamationmark.circle"
        }
    }
}

#Preview("Unusable") {
    SavedCommuteFailureView(failure: .unusable)
}

#Preview("Unreadable") {
    SavedCommuteFailureView(failure: .unreadable)
}

#Preview("Unexpected") {
    SavedCommuteFailureView(failure: .unexpected)
}
