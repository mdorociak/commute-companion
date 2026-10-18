import Foundation

struct DepartureRequestErrorDTO: Decodable, Sendable {
    let code: String
    let reference: String?

    var unknownStationRole: DepartureStationRole? {
        guard code == "unknown_station", let reference else { return nil }

        switch reference {
        case "station_id":
            return .origin

        case "towards":
            return .onward

        default:
            return nil
        }
    }

    var isOutsideFeedValidity: Bool {
        code == "outside_feed_validity"
    }
}
