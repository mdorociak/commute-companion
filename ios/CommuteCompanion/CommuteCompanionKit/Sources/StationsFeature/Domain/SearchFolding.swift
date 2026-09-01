import Foundation

extension String {
    var foldedForSearch: String {
        let folded = folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )

        return String(folded.map { String.strokeFoldings[$0] ?? $0 })
    }

    private static let strokeFoldings: [Character: Character] = [
        "ł": "l",
        "đ": "d",
        "ø": "o",
        "ħ": "h",
        "ŧ": "t",
    ]
}
