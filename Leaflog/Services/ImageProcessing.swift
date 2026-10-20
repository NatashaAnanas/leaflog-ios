import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

struct ProcessedImage: Sendable {
    var full: Data
    var thumb: Data
    /// Дата съёмки из метаданных, если есть.
    var takenAt: Date?
}

enum ImageProcessingError: LocalizedError {
    case undecodable, encodeFailed
    var errorDescription: String? {
        switch self {
        case .undecodable: String(localized: "Не удалось прочитать изображение.")
        case .encodeFailed: String(localized: "Не удалось подготовить изображение.")
        }
    }
}

/// Тяжёлая обработка: вызывать вне главного потока.
enum ImageProcessing {
    static let fullMaxPixels = 2048
    static let thumbMaxPixels = 480

    static func process(_ data: Data) throws -> ProcessedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw ImageProcessingError.undecodable }
        let taken = exifDate(source)
        let full = try jpeg(source, maxPixels: fullMaxPixels, quality: 0.85)
        let thumb = try jpeg(source, maxPixels: thumbMaxPixels, quality: 0.75)
        return ProcessedImage(full: full, thumb: thumb, takenAt: taken)
    }

    /// Миниатюра из уже сохранённого полноразмерного JPEG (при импорте резервной копии).
    static func thumbnail(fromFull data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw ImageProcessingError.undecodable }
        return try jpeg(source, maxPixels: thumbMaxPixels, quality: 0.75)
    }

    static func isDecodable(_ data: Data) -> Bool {
        guard let s = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(s) > 0
    }

    private static func jpeg(_ source: CGImageSource, maxPixels: Int, quality: CGFloat) throws -> Data {
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else {
            throw ImageProcessingError.undecodable
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageProcessingError.encodeFailed
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageProcessingError.encodeFailed }
        return out as Data
    }

    private static func exifDate(_ source: CGImageSource) -> Date? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let s = (exif[kCGImagePropertyExifDateTimeOriginal] ?? exif[kCGImagePropertyExifDateTimeDigitized]) as? String
        else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: s)
    }
}
