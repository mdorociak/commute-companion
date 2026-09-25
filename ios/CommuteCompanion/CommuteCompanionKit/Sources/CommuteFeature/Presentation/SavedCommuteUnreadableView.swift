import SwiftUI

public struct SavedCommuteUnreadableView: View {
    private let retry: () -> Void

    public init(retry: @escaping () -> Void) {
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label {
                Text("Saved commute unavailable")
            } icon: {
                Image(systemName: "externaldrive.badge.exclamationmark")
            }
        } description: {
            Text("Your saved commute could not be opened.")
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Unreadable") {
    SavedCommuteUnreadableView(retry: {})
}

#Preview("Unreadable – Accessibility text") {
    SavedCommuteUnreadableView(retry: {})
        .environment(\.dynamicTypeSize, .accessibility3)
}
