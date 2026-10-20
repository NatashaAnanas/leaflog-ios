import Foundation
import UIKit

/// Постоянное приватное хранилище изображений приложения (копии, не ссылки на медиатеку).
final class PhotoStore: @unchecked Sendable {
    let root: URL
    private var photosDir: URL { root.appendingPathComponent("Photos", isDirectory: true) }
    private var thumbsDir: URL { root.appendingPathComponent("Thumbs", isDirectory: true) }
    private let fm = FileManager.default

    init(root: URL) {
        self.root = root
        try? fm.createDirectory(at: photosDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
    }

    static var defaultRoot: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Leaflog", isDirectory: true)
    }

    func fullURL(_ id: UUID) -> URL { photosDir.appendingPathComponent("\(id.uuidString).jpg") }
    func thumbURL(_ id: UUID) -> URL { thumbsDir.appendingPathComponent("\(id.uuidString).jpg") }

    func write(_ image: ProcessedImage, id: UUID) throws {
        try image.full.write(to: fullURL(id), options: .atomic)
        do { try image.thumb.write(to: thumbURL(id), options: .atomic) }
        catch { try? fm.removeItem(at: fullURL(id)); throw error }
    }

    func writeFull(_ data: Data, id: UUID) throws {
        try data.write(to: fullURL(id), options: .atomic)
        let thumb = try ImageProcessing.thumbnail(fromFull: data)
        try thumb.write(to: thumbURL(id), options: .atomic)
    }

    func readFull(_ id: UUID) throws -> Data { try Data(contentsOf: fullURL(id)) }
    func exists(_ id: UUID) -> Bool { fm.fileExists(atPath: fullURL(id).path) }

    /// Удаляет только файлы внутри приложения; оригиналы в медиатеке не затрагиваются.
    func delete(_ id: UUID) {
        try? fm.removeItem(at: fullURL(id))
        try? fm.removeItem(at: thumbURL(id))
        ImageCache.shared.evict(id)
    }

    func allStoredIDs() -> Set<UUID> {
        let names = (try? fm.contentsOfDirectory(atPath: photosDir.path)) ?? []
        return Set(names.compactMap { UUID(uuidString: ($0 as NSString).deletingPathExtension) })
    }

    /// Удаляет файлы, на которые не ссылается ни одна запись. Вызывать только после успешной загрузки базы.
    @discardableResult
    func removeOrphans(keeping valid: Set<UUID>) -> Int {
        let orphans = allStoredIDs().subtracting(valid)
        orphans.forEach(delete)
        return orphans.count
    }
}

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    init() { cache.countLimit = 300 }

    private func key(_ id: UUID, _ thumb: Bool) -> NSString { "\(id.uuidString)-\(thumb ? "t" : "f")" as NSString }
    func image(_ id: UUID, thumb: Bool) -> UIImage? { cache.object(forKey: key(id, thumb)) }
    func store(_ image: UIImage, _ id: UUID, thumb: Bool) { cache.setObject(image, forKey: key(id, thumb)) }
    func evict(_ id: UUID) { cache.removeObject(forKey: key(id, true)); cache.removeObject(forKey: key(id, false)) }

    /// Декодирование вне главного потока.
    func load(_ id: UUID, thumb: Bool, store photos: PhotoStore) async -> UIImage? {
        if let cached = image(id, thumb: thumb) { return cached }
        let url = thumb ? photos.thumbURL(id) : photos.fullURL(id)
        let img: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let raw = UIImage(contentsOfFile: url.path) else { return nil }
            return raw.preparingForDisplay() ?? raw
        }.value
        if let img { store(img, id, thumb: thumb) }
        return img
    }
}
