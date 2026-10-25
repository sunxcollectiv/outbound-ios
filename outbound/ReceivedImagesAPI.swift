//
//  ReceivedImagesAPI.swift
//  outbound
//

import Foundation

/// `ImageReceiptRead` — an uploaded image as the received-item pipeline records it.
/// `tripId` is set once the image's bookings are imported into a trip.
struct ImageReceipt: Decodable {
    let id: String
    let tripId: String?
    let status: String
}

/// `ImageImportResult` — what became of an uploaded image once processed: placed in a
/// trip (`tripId`, with `itemCount` new items), or `no_match` / `ambiguous` (with the
/// trips it could fit) / `skipped` (not a confident booking).
struct ImageImportResult: Decodable {
    let receipt: ImageReceipt
    let outcome: String
    let tripId: String?
    let itemCount: Int
}

/// Request shapes for uploaded images (booking screenshots).
///
///     POST /received/images/upload   multipart `file` -> ImageReceiptRead (201)
///     POST /received/images/process  multipart `file` -> ImageImportResult (201)
enum ReceivedImagesAPI {
    /// Uploads one image into the received-item pipeline, without processing it.
    static func upload(_ file: MultipartFile) -> Endpoint {
        Endpoint(path: "/received/images/upload", method: .post, rawBody: file.body, timeout: 60)
    }

    /// Uploads one image and runs the whole pipeline on it in the same call: store,
    /// read the booking out of it, and import it into the matching trip. Given two
    /// minutes, since reading the booking can take a while.
    static func process(_ file: MultipartFile) -> Endpoint {
        Endpoint(path: "/received/images/process", method: .post, rawBody: file.body, timeout: 120)
    }
}
