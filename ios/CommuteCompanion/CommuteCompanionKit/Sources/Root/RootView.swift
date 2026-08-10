import Foundation
import SwiftUI
import APIClient
import StationsFeature

public struct RootView: View {
    private let stationsView: StationsView

    public init(baseURL: URL) {
        let apiClient = APIClient(baseURL: baseURL)
        stationsView = StationsView(apiClient: apiClient)
    }

    public var body: some View {
        NavigationStack {
            stationsView
        }
    }
}
