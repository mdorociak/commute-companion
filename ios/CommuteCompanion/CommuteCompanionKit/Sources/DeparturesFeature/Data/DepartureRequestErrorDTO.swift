import Foundation

struct DepartureRequestErrorDTO: Decodable, Sendable {
    let code: String
    let reference: String

    var unknownStationRole: DepartureStationRole? {
        guard code == "unknown_station" else { return nil }

        switch reference {
        case "station_id":
            return .origin

        case "towards":
            return .onward

        default:
            return nil
        }
    }
}
