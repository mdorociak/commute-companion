import Foundation
import Testing
@testable import DeparturesFeature

@Test
func departureResponseDecodesAndMapsToDomain() throws {
    let data = Data(
        #"""
        [
          {
            "id": "dep_f8a9c26b8a9d5f00bb6386d420915e62",
            "line": "D7",
            "destination": "Sędzisław",
            "departure_time": "2026-05-20T05:36:00+02:00",
            "platform": "II"
          },
          {
            "id": "dep_0f124ae208e45dfa7a891fb9b9465a31",
            "line": "D1",
            "destination": null,
            "departure_time": "2026-05-20T06:11:00+02:00",
            "platform": null
          }
        ]
        """#.utf8
    )

    let response = try JSONDecoder().decode([DepartureDTO].self, from: data)

    #expect(response.map { $0.toDomain() } == [
        Departure(
            id: "dep_f8a9c26b8a9d5f00bb6386d420915e62",
            line: "D7",
            destination: "Sędzisław",
            scheduledAt: try Date("2026-05-20T03:36:00Z", strategy: .iso8601),
            platform: "II"
        ),
        Departure(
            id: "dep_0f124ae208e45dfa7a891fb9b9465a31",
            line: "D1",
            destination: nil,
            scheduledAt: try Date("2026-05-20T04:11:00Z", strategy: .iso8601),
            platform: nil
        )
    ])
}

@Test
func departureResponseWithInvalidTimestampFailsDecoding() {
    let data = Data(
        #"""
        [
          {
            "id": "dep_f8a9c26b8a9d5f00bb6386d420915e62",
            "line": "D7",
            "destination": "Sędzisław",
            "departure_time": "not-a-timestamp",
            "platform": "II"
          }
        ]
        """#.utf8
    )

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode([DepartureDTO].self, from: data)
    }
}
