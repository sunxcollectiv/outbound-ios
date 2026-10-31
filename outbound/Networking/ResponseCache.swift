//
//  ResponseCache.swift
//  outbound
//

import CryptoKit
import Foundation

/// Keeps the last good response of selected GET requests on disk (the trip list and
/// each itinerary), plus the area photos on their covers, so trips can be opened with
/// no connection: in airplane mode, or somewhere with no signal.
///
/// Responses are stored as the server's raw JSON, so they decode exactly like a live
/// one. Kept in Application Support rather than Caches, which the system may purge
/// right when a traveler needs it, and excluded from backups. Holds one user's data,
/// so it's cleared on sign-out.
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

    /// Deletes everything saved except what's under `keys`, e.g. to drop trips the
    /// user is no longer on and photos that have been replaced.
    func removeAll(except keys: Set<String>) {
        let kept = Set(keys.map { fileURL(for: $0).lastPathComponent })
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where !kept.contains(file.lastPathComponent) {
            try? fileManager.removeItem(at: file)
        }
    }

    /// A file per key, named after it with anything but letters, digits and dashes
    /// replaced, e.g. "/trips/abc/itinerary" -> "_trips_abc_itinerary". Keys too long
    /// for a file name (photo URLs) are hashed instead.
    private func fileURL(for key: String) -> URL {
        var name = String(key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
        if name.count > 120 {
            name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        return directory.appending(path: name)
    }
}
