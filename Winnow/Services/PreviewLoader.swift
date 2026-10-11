import AppKit
import CoreImage
import ImageIO

/// Limits concurrent card reads. SD cards are slow at random reads, so about 4 at once.
/// Waiters whose task is cancelled (a cell scrolled away) leave the queue without reading.
actor AsyncLimiter {
    private var available: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    init(limit: Int) { available = limit }

    func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    c.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, c))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: i).continuation.resume(throwing: CancellationError())
    }

    func release() {
        if waiters.isEmpty {
            available += 1
        } else {
            // Newest first: the cells the user is looking at now.
            waiters.removeLast().continuation.resume()
        }
    }

    nonisolated func run<T: Sendable>(_ body: @Sendable () throws -> T) async throws -> T {
        try await acquire()
        let result = Result { try body() }
        await release()
        return try result.get()
    }
}

private final class ImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

final class PreviewLoader: @unchecked Sendable {
    /// Thumbnail pixel sizes. Requests snap up to one of these so dragging the size slider
    /// doesn't refetch on every step.
    static let buckets = [320, 480, 640, 840]
    static let loupePixels = 3200

    private let cache = NSCache<NSString, ImageBox>()
    private let gridLimiter = AsyncLimiter(limit: 4)
    private let loupeLimiter = AsyncLimiter(limit: 2)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    init() {
        cache.totalCostLimit = 1_500_000_000
    }

    static func bucket(forPixels px: CGFloat) -> Int {
        buckets.first { CGFloat($0) >= px } ?? buckets.last!
    }

    private func key(_ id: String, _ size: Int) -> NSString { "\(id)#\(size)" as NSString }

    private func store(_ image: CGImage, id: String, size: Int) {
        cache.setObject(ImageBox(image), forKey: key(id, size), cost: image.bytesPerRow * image.height)
    }

    func cached(_ id: String, size: Int) -> CGImage? {
        cache.object(forKey: key(id, size))?.image
    }

    /// Best image already in memory for this photo, used as a placeholder while a sharper one loads.
    func bestCached(_ id: String, preferring size: Int) -> CGImage? {
        if let exact = cached(id, size: size) { return exact }
        if let loupe = cached(id, size: Self.loupePixels) { return loupe }
        for b in Self.buckets.reversed() { if let img = cached(id, size: b) { return img } }
        return nil
    }

    func thumbnail(for photo: Photo, bucket: Int) async -> CGImage? {
        if let hit = cached(photo.id, size: bucket) { return hit }
        guard let image = try? await gridLimiter.run({ Self.decode(photo, maxPixels: bucket) }) ?? nil else {
            return nil
        }
        store(image, id: photo.id, size: bucket)
        return image
    }

    /// Screen-resolution image for the loupe: the JPG sibling or the RAF's embedded preview.
    func loupeImage(for photo: Photo) async -> CGImage? {
        if let hit = cached(photo.id, size: Self.loupePixels) { return hit }
        guard let image = try? await loupeLimiter.run({ Self.decode(photo, maxPixels: Self.loupePixels) }) ?? nil else {
            return nil
        }
        store(image, id: photo.id, size: Self.loupePixels)
        return image
    }

    /// Full-resolution image for 100% zoom. Decodes the RAF with CIRAWFilter, or the full JPG.
    func fullResolution(for photo: Photo) async -> CGImage? {
        let fullKey = Int.max
        if let hit = cached(photo.id, size: fullKey) { return hit }
        let context = ciContext
        guard let image = try? await loupeLimiter.run({ () -> CGImage? in
            if let raf = photo.raf, let filter = CIRAWFilter(imageURL: raf), let output = filter.outputImage {
                return context.createCGImage(output, from: output.extent, format: .RGBA8,
                                             colorSpace: CGColorSpace(name: CGColorSpace.displayP3))
            }
            if let jpg = photo.jpg, let src = CGImageSourceCreateWithURL(jpg as CFURL, nil) {
                return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
                    .flatMap { Self.applyOrientation($0, source: src) }
            }
            return nil
        }) ?? nil else { return nil }
        store(image, id: photo.id, size: fullKey)
        return image
    }

    func prefetchLoupe(_ photos: [Photo]) {
        for p in photos where cached(p.id, size: Self.loupePixels) == nil {
            Task.detached(priority: .utility) { [self] in _ = await loupeImage(for: p) }
        }
    }

    // MARK: Decoding

    static func decode(_ photo: Photo, maxPixels: Int) -> CGImage? {
        let noCache = [kCGImageSourceShouldCache: false] as CFDictionary
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        // The RAF carries a camera-rendered JPEG preview. Read whichever is fewer bytes off the card:
        // on recent bodies the embedded preview is often a third the size of the JPG sibling.
        let embedded = photo.raf.flatMap(RAFFile.embeddedJPEGRange)
        let jpgIsCheaper = photo.jpg != nil && (embedded == nil || photo.jpgSize <= Int64(embedded!.length))
        if jpgIsCheaper, let jpg = photo.jpg, let src = CGImageSourceCreateWithURL(jpg as CFURL, noCache),
           let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
            return image
        }
        guard let raf = photo.raf else { return nil }
        if let range = embedded, let data = RAFFile.readBytes(raf, offset: range.offset, length: range.length),
           let src = CGImageSourceCreateWithData(data as CFData, noCache),
           let image = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) {
            return image
        }
        guard let src = CGImageSourceCreateWithURL(raf as CFURL, noCache) else { return nil }
        let fallback: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, fallback as CFDictionary)
    }

    /// Full decode of a JPG ignores EXIF orientation; rotate via a full-size thumbnail instead.
    private static func applyOrientation(_ image: CGImage, source: CGImageSource) -> CGImage? {
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] as? Int ?? 1
        guard orientation != 1 else { return image }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) ?? image
    }
}
