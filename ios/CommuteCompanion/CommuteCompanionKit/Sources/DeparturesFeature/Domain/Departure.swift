import Foundation

struct Departure: Identifiable, Equatable, Sendable {
    let id: String
    let line: String
    let destination: String?
    let scheduledAt: Date
    let platform: String?
}
