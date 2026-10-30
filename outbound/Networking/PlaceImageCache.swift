//
//  PlaceImageCache.swift
//  outbound
//

import UIKit

/// Loads place cover photos and keeps them in memory for the app session, so a card
/// rebuilt by a day swipe or a return to the trip shows its photo instantly instead
/// of re-requesting it (each load of a cover `url` is a billed Google Place Photo
/// request).
///
/// `shared` is memory only, by design: Google's terms don't allow storing Places
/// photos, so nothing is written to disk — the session is ephemeral with no URL
/// cache, and `NSCache` drops images under memory pressure. A cold launch fetches
/// again.
///
/// `areaPhotos` also saves to disk, so trip covers still show offline: they're
/// Unsplash photos, which may be kept on the device (still loaded from Unsplash's
/// own URLs). They're saved alongside the saved trips and cleared with them on
/// sign-out.
final class PlaceImageCache {
    static let shared = PlaceImageCache()
    /// For areas' Unsplash photos, kept on disk as well as in memory.
    static let areaPhotos = PlaceImageCache(disk: .shared)

    private let session: URLSession
    private let images = NSCache<NSURL, UIImage>()
    /// Where loaded images are also saved, if anywhere; nil keeps them in memory only.
    private let disk: ResponseCache?
    /// Loads in flight, so cards showing the same place share one request.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init(protocolClasses: [AnyClass]? = nil, disk: ResponseCache? = nil) {
        self.disk = disk
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let protocolClasses { config.protocolClasses = protocolClasses }
        session = URLSession(configuration: config)
        // Roughly 100 MB of decoded bitmaps; an 800px cover is a few MB.
        images.totalCostLimit = 100 * 1024 * 1024
    }

    /// The image for `url` if it's already loaded this session.
    func cachedImage(for url: URL) -> UIImage? {
        images.object(forKey: url as NSURL)
    }

    /// The image for `url`, from memory, from disk, or loaded now. Nil when the request or
    /// decoding fails (e.g. a 403 once the photo reference expires); failures aren't
    /// remembered, so a later view tries again.
    func image(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let task = inFlight[url] { return await task.value }

        let task = Task { await load(url) }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image {
            images.setObject(image, forKey: url as NSURL, cost: image.memoryCost)
        }
        return image
    }

    private func load(_ url: URL) async -> UIImage? {
        let key = "photo:" + url.absoluteString
        if let data = disk?.data(for: key), let image = UIImage(data: data) {
            return await image.byPreparingForDisplay() ?? image
        }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        disk?.store(data, for: key)
        // Decode off the main thread now, rather than on first draw mid-scroll.
        return await image.byPreparingForDisplay() ?? image
    }
}

private extension UIImage {
    /// Approximate decoded size in bytes, for the cache's cost limit.
    var memoryCost: Int {
        guard let cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
