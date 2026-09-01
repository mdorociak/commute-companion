import Foundation
import Testing
@testable import StationsFeature

@Suite
struct SearchFoldingTests {

    @Test
    func strokeLettersFoldToTheirBaseLetter() {
        #expect("Wrocław".foldedForSearch == "wroclaw")
    }

    @Test
    func combiningMarksAreRemoved() {
        #expect("Główny".foldedForSearch == "glowny")
    }
}
