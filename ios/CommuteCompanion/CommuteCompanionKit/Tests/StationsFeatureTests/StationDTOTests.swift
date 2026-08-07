import Foundation
import Testing
@testable import StationsFeature

@Test
func stationResponseDecodesAndMapsToDomain() throws {
    let data = Data(
        #"""
        [
          {
            "id": "2246799",
            "name": "Brzeg",
            "code": null,
            "lat": 50.852881,
            "lon": 17.470911,
            "platforms": [
              { "id": "2333170", "code": "II" }
            ]
          }
        ]
        """#.utf8
    )

    let response = try JSONDecoder().decode([StationDTO].self, from: data)
    let stationDTO = try #require(response.first)

    #expect(response.count == 1)
    #expect(stationDTO.toDomain() == Station(
        id: "2246799",
        name: "Brzeg",
        code: nil
    ))
}

@Test
func stationResponseWithoutRequiredIDFailsDecoding() {
    let data = Data(
        #"""
        [
          {
            "name": "Brzeg",
            "code": "11",
            "lat": 50.852881,
            "lon": 17.470911,
            "platforms": []
          }
        ]
        """#.utf8
    )

    do {
        _ = try JSONDecoder().decode([StationDTO].self, from: data)
        Issue.record("Expected the missing station ID to fail decoding")
    } catch {
        #expect(error is DecodingError)
    }
}
