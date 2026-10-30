//
//  ResponseCache.swift
//  outbound
//

import Foundation

/// Keeps the last good response of selected GET requests on disk (the trip list and
/// each itinerary), so trips can be opened with no connection: in airplane mode, or
/// somewhere with no signal.
///
/// Stored as the server's raw JSON, so it decodes exactly like a live response. Kept
/// in Application Support rather than Caches, which the system may purge right when a
/// traveler needs it, and excluded from backups. Holds one user's data, so it's
/// cleared on sign-out.
final class ResponseCache {
    static let shared = ResponseCache()

    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL = URL.applicationSupportDirectory.appending(path: "ResponseCache", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    /// The saved response for `key`, if there is one.
    func data(for key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    /// When the response for `key` was saved.
    func savedDate(for key: String) -> Date? {
        try? fileURL(for: key).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// Saves `data` as the response for `key`, replacing any earlier one. Best-effort:
    /// a failed write just leaves the older copy.
    func store(_ data: Data, for key: String) {
        do {
            if !fileManager.fileExists(atPath: directory.path()) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                var excluded = URLResourceValues()
                excluded.isExcludedFromBackup = true
                var directory = directory
                try directory.setResourceValues(excluded)
            }
            try data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // Offline viewing just falls back to the previous copy, if any.
        }
    }

    /// Deletes everything saved, e.g. when the user signs out.
    func removeAll() {
        try? fileManager.removeItem(at: directory)
    }

    /// A file per key, named after it with anything but letters and digits replaced,
    /// e.g. "/trips/abc/itinerary" -> "_trips_abc_itinerary.json".
    private func fileURL(for key: String) -> URL {
        let name = String(key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        return directory.appending(path: "\(name).json")
    }
}
