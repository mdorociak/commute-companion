
import Foundation
import SwiftUI
import Root

@main
struct CommuteCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(baseURL: DevelopmentConfiguration.apiBaseURL)
        }
    }
}

private enum DevelopmentConfiguration {
    static let apiBaseURL: URL = {
        guard let url = URL(string: "http://127.0.0.1:8000") else {
            preconditionFailure("Invalid development API base URL")
        }

        return url
    }()
}
