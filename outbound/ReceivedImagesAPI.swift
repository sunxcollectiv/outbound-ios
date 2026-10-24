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

/// Request shapes for uploaded images (booking screenshots).
///
///     POST /received/images/upload  multipart `file` -> ImageReceiptRead (201)
enum ReceivedImagesAPI {
    /// Uploads one image into the received-item pipeline. Given a minute, since the
    /// server may read the bookings out of it before responding.
    static func upload(_ file: MultipartFile) -> Endpoint {
        Endpoint(path: "/received/images/upload", method: .post, rawBody: file.body, timeout: 60)
    }
}
