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
    /// A body sent as is with its content type (e.g. a multipart upload), instead of
    /// `body` encoded as JSON.
    var rawBody: (data: Data, contentType: String)?
    /// How long to wait for the response; nil uses the session's default.
    var timeout: TimeInterval?
    var requiresAuth = true
    /// Keep the last successful response on disk, so it can still be shown offline
    /// (read back with `APIClient.cached(_:as:)`). For GETs only.
    var cachesResponse = false

    /// What a cached response is saved under.
    var cacheKey: String {
        query.isEmpty ? path : path + "?" + query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }
}

/// A `multipart/form-data` body carrying one file, as FastAPI's `UploadFile` expects.
struct MultipartFile {
    let field: String
    let filename: String
    let contentType: String
    let data: Data

    private let boundary = "Boundary-\(UUID().uuidString)"

    var body: (data: Data, contentType: String) {
        var data = Data()
        data.append(Data("--\(boundary)\r\n".utf8))
        data.append(Data("Content-Disposition: form-data; name=\"\(field)\"; filename=\"\(filename)\"\r\n".utf8))
        data.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        data.append(self.data)
        data.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return (data, "multipart/form-data; boundary=\(boundary)")
    }
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
    static let shared = APIClient(connectivity: .shared)

    var token: String?

    private let baseURL: URL
    private let session: URLSession
    private let cache: ResponseCache

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

    /// Told whether requests reach the server; nil for clients that shouldn't affect
    /// the app's offline state, e.g. in tests.
    private let connectivity: Connectivity?

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared, cache: ResponseCache = .shared, connectivity: Connectivity? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.cache = cache
        self.connectivity = connectivity
    }

    /// Sends a request and decodes the JSON response. `onBodySent` is called once the
    /// whole request body has gone out, e.g. to tell an upload from the server's work
    /// on it.
    func send<Response: Decodable>(
        _ endpoint: Endpoint, as type: Response.Type = Response.self, onBodySent: (@Sendable () -> Void)? = nil
    ) async throws -> Response {
        let data = try await perform(endpoint, onBodySent: onBodySent)
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

    /// The last successful response to a `cachesResponse` endpoint, decoded, or nil if
    /// none was saved (or it no longer decodes).
    func cached<Response: Decodable>(_ endpoint: Endpoint, as type: Response.Type = Response.self) -> Response? {
        guard let data = cache.data(for: endpoint.cacheKey) else { return nil }
        return try? decoder.decode(Response.self, from: data)
    }

    /// When the cached response to `endpoint` was saved.
    func cachedDate(for endpoint: Endpoint) -> Date? {
        cache.savedDate(for: endpoint.cacheKey)
    }

    /// Saves `value` as the cached response to `endpoint`, for a copy changed locally
    /// (e.g. a trip edited in place) so it's what shows offline.
    func storeCached(_ value: some Encodable, for endpoint: Endpoint) {
        guard let data = try? encoder.encode(value) else { return }
        cache.store(data, for: endpoint.cacheKey)
    }

    private func perform(_ endpoint: Endpoint, onBodySent: (@Sendable () -> Void)? = nil) async throws -> Data {
        let request = try makeRequest(for: endpoint)
        let sentToken = token

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: onBodySent.map(BodySentDelegate.init))
        } catch URLError.networkConnectionLost {
            // A kept-alive connection the server closed while the app was suspended
            // (e.g. woken for a push action); the request never went out, so try once
            // more on a fresh connection.
            do {
                (data, response) = try await session.data(for: request, delegate: onBodySent.map(BodySentDelegate.init))
            } catch {
                throw networkError(error)
            }
        } catch {
            throw networkError(error)
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        // A gateway answering for a server that's down counts as not reaching it.
        if Connectivity.gatewayStatuses.contains(http.statusCode) {
            connectivity?.serverUnreachable()
        } else {
            connectivity?.serverResponded()
        }

        switch http.statusCode {
        case 200..<300:
            // Unless the user signed out while this was in flight, leaving the cache
            // cleared for whoever signs in next.
            if endpoint.cachesResponse, endpoint.method == .get, token == sentToken {
                cache.store(data, for: endpoint.cacheKey)
            }
            return data
        case 401 where endpoint.requiresAuth:
            // An authenticated request was rejected: the token is missing or expired.
            throw APIError.unauthorized
        default:
            // Includes a 401 from login (wrong credentials) — surface the server's message.
            throw APIError.server(status: http.statusCode, message: errorMessage(from: data))
        }
    }

    /// Wraps a failed request's error, and tells `connectivity` when it means the
    /// server can't be reached (rather than, say, a cancelled request).
    private func networkError(_ error: Error) -> APIError {
        let unreachable: [URLError.Code] = [
            .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut,
            .networkConnectionLost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        ]
        if let code = (error as? URLError)?.code, unreachable.contains(code) {
            connectivity?.serverUnreachable()
        }
        return .network(error)
    }

    private func makeRequest(for endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: endpoint.path), resolvingAgainstBaseURL: false)!
        if !endpoint.query.isEmpty {
            components.queryItems = endpoint.query
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let raw = endpoint.rawBody {
            request.setValue(raw.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = raw.data
        } else if let body = endpoint.body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        if let timeout = endpoint.timeout {
            request.timeoutInterval = timeout
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

/// Reports when a task has sent its whole request body.
private final class BodySentDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onBodySent: @Sendable () -> Void
    private var reported = false

    init(_ onBodySent: @escaping @Sendable () -> Void) {
        self.onBodySent = onBodySent
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64, totalBytesExpectedToSend: Int64
    ) {
        guard !reported, totalBytesSent >= totalBytesExpectedToSend else { return }
        reported = true
        onBodySent()
    }
}
