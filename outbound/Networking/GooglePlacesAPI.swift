//
//  GooglePlacesAPI.swift
//  outbound
//

import Foundation

/// A single place suggestion returned by Google Places Autocomplete.
///
/// `mainText` is the place's name (e.g. "Tokyo Tower") and `secondaryText` is the
/// supporting address line (e.g. "4 Chome-2-8 Shibakoen, Minato City, Tokyo"). The
/// `placeId` is kept so a later step can fetch full details (coordinates, etc.) when
/// locations are wired into trip items.
enum GooglePlacesError: LocalizedError {
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Place search isn't configured. Add a Google Places key to Secrets.json."
        }
    }
}

struct PlaceSuggestion: Identifiable, Equatable {
    let placeId: String
    let mainText: String
    let secondaryText: String?

    var id: String { placeId }
}

/// Talks to the Google Places API (New) for place search.
///
/// This is a separate service from the Outbound backend — a different host that
/// authenticates with an API key header rather than a bearer token — so it has its
/// own tiny client instead of going through `APIClient`. The new Places API returns
/// camelCase JSON, so no key-conversion strategy is needed.
final class GooglePlacesClient {
    static let shared = GooglePlacesClient()

    /// The API key, loaded from the gitignored `Secrets.json` bundled with the app.
    /// See `Secrets.example.json` for setup. Restrict the key to this app's bundle id
    /// and the Places API in the Google Cloud console.
    private let apiKey: String
    private let endpoint = URL(string: "https://places.googleapis.com/v1/places:autocomplete")!
    private let session: URLSession

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
        self.apiKey = Self.loadAPIKey()
    }

    /// Reads `GooglePlacesAPIKey` from the bundled `Secrets.json`. Returns an empty
    /// string if the file or key is missing, which surfaces as a clear error on use.
    private static func loadAPIKey() -> String {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["GooglePlacesAPIKey"] as? String else {
            return ""
        }
        return key
    }

    private struct AutocompleteRequest: Encodable {
        let input: String
    }

    private struct AutocompleteResponse: Decodable {
        let suggestions: [Suggestion]?

        struct Suggestion: Decodable {
            let placePrediction: PlacePrediction?
        }

        struct PlacePrediction: Decodable {
            let placeId: String
            let structuredFormat: StructuredFormat?
            let text: LocalizedText?
        }

        struct StructuredFormat: Decodable {
            let mainText: LocalizedText?
            let secondaryText: LocalizedText?
        }

        struct LocalizedText: Decodable {
            let text: String
        }
    }

    /// Returns place suggestions for the given free-text input.
    ///
    /// Returns an empty array for blank input. Throws on network or decoding failures.
    func autocomplete(_ input: String) async throws -> [PlaceSuggestion] {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard !apiKey.isEmpty else {
            throw GooglePlacesError.missingAPIKey
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.httpBody = try encoder.encode(AutocompleteRequest(input: trimmed))

        let (data, _) = try await session.data(for: request)
        let response = try decoder.decode(AutocompleteResponse.self, from: data)

        return (response.suggestions ?? []).compactMap { suggestion in
            guard let prediction = suggestion.placePrediction else { return nil }
            // Prefer the structured name; fall back to the full text when it's missing.
            let main = prediction.structuredFormat?.mainText?.text ?? prediction.text?.text
            guard let main else { return nil }
            return PlaceSuggestion(
                placeId: prediction.placeId,
                mainText: main,
                secondaryText: prediction.structuredFormat?.secondaryText?.text
            )
        }
    }
}
