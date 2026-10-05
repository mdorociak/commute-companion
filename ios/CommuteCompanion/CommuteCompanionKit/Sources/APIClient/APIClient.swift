import Foundation

public enum APIError: Error, Equatable, Sendable {
    case invalidURL
    case unreachable
    case invalidResponse
    case httpStatus(Int, body: Data)
    case decoding
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

        let response = try await send(request)
        guard 200..<300 ~= response.statusCode else {
            throw APIError.httpStatus(response.statusCode, body: response.data)
        }

        do {
            return try JSONDecoder().decode(responseType, from: response.data)
        } catch {
            throw APIError.decoding
        }
    }

    private func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            return try await transport.response(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code.meansUnreachable {
            throw APIError.unreachable
        }
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

private extension URLError.Code {
    var meansUnreachable: Bool {
        switch self {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .dataNotAllowed,
             .internationalRoamingOff,
             .callIsActive,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .timedOut:
            true

        default:
            false
        }
    }
}
