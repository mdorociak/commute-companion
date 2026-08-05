import Foundation

public enum APIError: Error, Equatable, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The request URL is invalid"
        case .invalidResponse:
            "The server returned an invalid response"
        case .httpStatus(let statusCode):
            "The server returned HTTP \(statusCode)"
        }
    }
}

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public protocol HTTPTransport: Sendable {
    func response(for request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
    }

    public func response(for request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        return HTTPResponse(data: data, statusCode: httpResponse.statusCode)
    }
}

public struct APIClient: Sendable {
    private let baseURL: URL
    private let transport: any HTTPTransport

    public init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    public func get<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        as responseType: Response.Type
    ) async throws -> Response {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let response = try await transport.response(for: request)
        guard 200..<300 ~= response.statusCode else {
            throw APIError.httpStatus(response.statusCode)
        }

        return try JSONDecoder().decode(responseType, from: response.data)
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }

        let slashes = CharacterSet(charactersIn: "/")
        let basePath = components.path.trimmingCharacters(in: slashes)
        let endpointPath = path.trimmingCharacters(in: slashes)
        components.path = [basePath, endpointPath]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.path.insert("/", at: components.path.startIndex)
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }
        return url
    }
}
