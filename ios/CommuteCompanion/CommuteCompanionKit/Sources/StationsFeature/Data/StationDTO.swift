struct StationDTO: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let code: String?

    func toDomain() -> Station {
        Station(id: id, name: name, code: code)
    }
}
