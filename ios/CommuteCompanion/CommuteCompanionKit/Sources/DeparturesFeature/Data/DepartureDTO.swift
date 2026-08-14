import Foundation

struct DepartureDTO: Decodable, Equatable, Sendable {
    let id: String
    let line: String
    let destination: String?
    let departureTime: Date
    let platform: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case line
        case destination
        case departureTime = "departure_time"
        case platform
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        line = try container.decode(String.self, forKey: .line)
        destination = try container.decodeIfPresent(
            String.self,
            forKey: .destination
        )
        platform = try container.decodeIfPresent(
            String.self,
            forKey: .platform
        )

        let departureTimeValue = try container.decode(
            String.self,
            forKey: .departureTime
        )
        guard let decodedDepartureTime = ISO8601DateFormatter().date(
            from: departureTimeValue
        ) else {
            throw DecodingError.dataCorruptedError(
                forKey: .departureTime,
                in: container,
                debugDescription: "Expected an ISO 8601 timestamp"
            )
        }
        departureTime = decodedDepartureTime
    }

    func toDomain() -> Departure {
        Departure(
            id: id,
            line: line,
            destination: destination,
            scheduledAt: departureTime,
            platform: platform
        )
    }
}
