import Testing
@testable import Root

@MainActor @Test
func rootViewCanBeCreated() {
    _ = RootView()
}
