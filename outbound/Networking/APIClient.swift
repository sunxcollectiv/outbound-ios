//
//  APIClient.swift
//  outbound
//

import Foundation

enum APIConfig {
    /// Debug builds (run from Xcode) talk to the local dev server; release builds use production.
    /// The Simulator shares the Mac's network, so `localhost` reaches a server running on this Mac.
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:4830")!
    #else
    static let baseURL = URL(string: "https://api.outbound.earth")!
    #endif
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// A single API request: where it goes, how, and what it sends.
struct Endpoint {
    var path: String
    var method: HTTPMethod = .get
    var query: [URLQueryItem] = []
    var body: (any Encodable)?
    var requiresAuth = true
}

enum APIError: LocalizedError {
    case unauthorized
    case server(status: Int, message: String?)
    case invalidResponse
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case .server(_, let message?):
            message
        case .server(let status, nil):
            "Something went wrong (error \(status)). Please try again."
        case .invalidResponse, .decoding:
            "We got an unexpected response from the server."
        case .network:
            "Couldn't reach the server. Check your connection and try again."
        }
    }
}

private extension ISO8601DateFormatter {
    static let standard = ISO8601DateFormatter()
    static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Sends requests to the Outbound backend.
///
/// Requests and responses are JSON with snake_case keys, which map to camelCase
/// Swift properties automatically. When a token is set, it's sent as
/// `Authorization: Bearer <token>`.
final class APIClient {
    static let shared = APIClient()

    var token: String?

    private let baseURL: URL
    private let session: URLSession

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // The backend sends ISO-8601 timestamps, sometimes with fractional seconds
        // (e.g. "2026-10-09T12:00:00.123456Z"), which `.iso8601` can't parse. Try
        // the fractional-seconds format first, then fall back to the plain one.
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter.withFractionalSeconds.date(from: string)
                ?? ISO8601DateFormatter.standard.date(from: string) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Unrecognized date format: \(string)")
            )
        }
        return decoder
    }()

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Sends a request and decodes the JSON response.
    func send<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) async throws -> Response {
        let data = try await perform(endpoint)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// Sends a request whose response body we don't need.
    func send(_ endpoint: Endpoint) async throws {
        _ = try await perform(endpoint)
    }

    private func perform(_ endpoint: Endpoint) async throws -> Data {
        let request = try makeRequest(for: endpoint)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401 where endpoint.requiresAuth:
            // An authenticated request was rejected: the token is missing or expired.
            throw APIError.unauthorized
        default:
            // Includes a 401 from login (wrong credentials) — surface the server's message.
            throw APIError.server(status: http.statusCode, message: errorMessage(from: data))
        }
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        if endpoint.requiresAuth, let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// Pulls a human-readable message out of an error body.
    ///
    /// FastAPI returns `{"detail": "..."}` for simple errors and
    /// `{"detail": [{"msg": "...", ...}]}` for validation errors; we also accept
    /// `{"error": "..."}` / `{"message": "..."}` as a fallback.
    private func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let detail = json["detail"] as? String { return detail }
        if let items = json["detail"] as? [[String: Any]] {
            let messages = items.compactMap { $0["msg"] as? String }
            if !messages.isEmpty { return messages.joined(separator: "\n") }
        }
        return json["message"] as? String ?? json["error"] as? String
    }
}
