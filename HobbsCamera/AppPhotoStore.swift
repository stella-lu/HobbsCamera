import Foundation
import ImageIO
import UniformTypeIdentifiers
import UIKit

/// Handles private sandbox storage for full-resolution photos and thumbnails.
///
/// Storage root:
/// Application Support/HobbsCamera/
///   - photos/
///   - thumbnails/
///
/// Notes:
/// - Both directories (and files) are excluded from iCloud backups.
/// - Full-res JPEGs are stamped to ensure timestamp metadata is present.
/// - This file also provides URL resolution helpers to support:
///   - portable persistence (store filenames)
///   - legacy persistence (absolute paths from older dev runs)
enum AppPhotoStore {
    private static let appFolderName = "HobbsCamera"
    private static let photosFolderName = "photos"
    private static let thumbnailsFolderName = "thumbnails"

    // MARK: - Public API (Save)

    /// Saves the photo to private storage, stamps timestamp metadata, and returns the saved photo URL.
    /// New code should store `url.lastPathComponent` (the filename) in SwiftData, not the absolute path.
    static func saveJPEGToPrivateLibrary(_ jpegData: Data, createdAt: Date) throws -> URL {
        let filename = "\(UUID().uuidString).jpg"
        let url = try photosDirectoryURL().appendingPathComponent(filename)

        let stampedData = try stampJPEGTimestampMetadata(jpegData: jpegData, createdAt: createdAt)
        try stampedData.write(to: url, options: [.atomic])

        try excludeFromBackup(url)
        return url
    }

    /// Generates and saves a thumbnail JPEG for an existing photo URL, returning the thumbnail URL.
    /// New code should store `thumbURL.lastPathComponent` (the filename) in SwiftData.
    static func generateAndSaveThumbnail(for photoURL: URL, maxPixelSize: Int = 500) throws -> URL {
        let data = try Data(contentsOf: photoURL)
        guard let image = UIImage(data: data) else {
            throw StoreError.thumbnailGenerationFailed
        }

        let thumb = image.scaledDownKeepingAspect(maxPixelSize: maxPixelSize)
        guard let jpegThumb = thumb.jpegData(compressionQuality: 0.82) else {
            throw StoreError.thumbnailGenerationFailed
        }

        let filename = photoURL.deletingPathExtension().lastPathComponent + "_thumb.jpg"
        let thumbURL = try thumbnailsDirectoryURL().appendingPathComponent(filename)

        try jpegThumb.write(to: thumbURL, options: [.atomic])
        try excludeFromBackup(thumbURL)

        return thumbURL
    }

    // MARK: - Public API (Directories)

    /// Public, stable directory URL for full-resolution photos.
    static func photosDirectoryURL() throws -> URL {
        try ensureDirectory(appSubdirectory: photosFolderName)
    }

    /// Public, stable directory URL for thumbnails.
    static func thumbnailsDirectoryURL() throws -> URL {
        try ensureDirectory(appSubdirectory: thumbnailsFolderName)
    }

    // MARK: - Public API (Resolution Helpers)

    /// Resolves either:
    /// - a legacy absolute path, or
    /// - a portable filename,
    /// into a valid on-disk URL inside the photos directory.
    static func resolvePhotoURL(from storedValue: String) -> URL? {
        resolveURL(from: storedValue) { try photosDirectoryURL() }
    }

    /// Resolves either:
    /// - a legacy absolute path, or
    /// - a portable filename,
    /// into a valid on-disk URL inside the thumbnails directory.
    static func resolveThumbnailURL(from storedValue: String) -> URL? {
        resolveURL(from: storedValue) { try thumbnailsDirectoryURL() }
    }

    // MARK: - Private (Resolution Core)

    /// Core resolver with backward compatibility.
    ///
    /// Resolution steps:
    /// 1) If `storedValue` looks like an absolute path and the file exists, use it.
    /// 2) Else treat `storedValue` as a filename in the expected directory.
    /// 3) Else fall back to `lastPathComponent` in the expected directory.
    private static func resolveURL(from storedValue: String, directory: () throws -> URL) -> URL? {
        let fm = FileManager.default

        // 1) Absolute-path happy path (legacy records).
        if storedValue.hasPrefix("/") {
            let absolute = URL(fileURLWithPath: storedValue)
            if fm.fileExists(atPath: absolute.path) {
                return absolute
            }
        }

        // 2) Filename path (new records).
        do {
            let dir = try directory()
            let candidate = dir.appendingPathComponent(storedValue)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }

            // 3) Fallback: if storedValue was an absolute path that no longer exists,
            // try reconstructing by filename.
            let last = URL(fileURLWithPath: storedValue).lastPathComponent
            if !last.isEmpty {
                let fallback = dir.appendingPathComponent(last)
                if fm.fileExists(atPath: fallback.path) {
                    return fallback
                }
            }

            // Even if not found, return the most reasonable candidate
            // so callers can attempt load and show an error state.
            return candidate
        } catch {
            return nil
        }
    }

    // MARK: - Private (Directory Management)

    private static func ensureDirectory(appSubdirectory: String) throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDir = base.appendingPathComponent(appFolderName, isDirectory: true)
        let dir = appDir.appendingPathComponent(appSubdirectory, isDirectory: true)

        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Exclude directories too.
        try excludeFromBackup(appDir)
        try excludeFromBackup(dir)

        return dir
    }

    // MARK: - Private (iCloud Backup Exclusion)

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true

        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    // MARK: - Private (Metadata Stamping)

    /// Ensures the output JPEG includes timestamp metadata.
    ///
    /// We stamp:
    /// - EXIF DateTimeOriginal
    /// - EXIF DateTimeDigitized
    /// - TIFF DateTime
    ///
    /// Format required by EXIF is: "yyyy:MM:dd HH:mm:ss"
    private static func stampJPEGTimestampMetadata(jpegData: Data, createdAt: Date) throws -> Data {
        guard let source = CGImageSourceCreateWithData(jpegData as CFData, nil) else {
            throw StoreError.metadataStampingFailed
        }

        let type = CGImageSourceGetType(source) as String?
        guard type == UTType.jpeg.identifier else {
            // Be conservative - avoid corrupting non-JPEG data.
            throw StoreError.metadataStampingFailed
        }

        // Read existing metadata (if present), mutate, then write into a new JPEG.
        let existing = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var mutable = existing

        let timestamp = ExifTimestampFormatter.format(createdAt)

        // EXIF
        var exif = (mutable[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        exif[kCGImagePropertyExifDateTimeOriginal] = timestamp
        exif[kCGImagePropertyExifDateTimeDigitized] = timestamp
        mutable[kCGImagePropertyExifDictionary] = exif

        // TIFF
        var tiff = (mutable[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
        tiff[kCGImagePropertyTIFFDateTime] = timestamp
        mutable[kCGImagePropertyTIFFDictionary] = tiff

        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            outData as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw StoreError.metadataStampingFailed
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.95
        ]

        CGImageDestinationAddImageFromSource(dest, source, 0, mutable as CFDictionary)
        CGImageDestinationSetProperties(dest, options as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw StoreError.metadataStampingFailed
        }

        return outData as Data
    }
}

// MARK: - Errors

enum StoreError: Error {
    case thumbnailGenerationFailed
    case metadataStampingFailed
}

// MARK: - Utilities

private enum ExifTimestampFormatter {
    static func format(_ date: Date) -> String {
        // Use UTC for consistency across devices/time zones.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension UIImage {
    func scaledDownKeepingAspect(maxPixelSize: Int) -> UIImage {
        let maxPixel = CGFloat(maxPixelSize)
        let w = size.width
        let h = size.height

        guard w > 0, h > 0 else { return self }

        let scale = min(maxPixel / w, maxPixel / h, 1.0)
        let newSize = CGSize(width: w * scale, height: h * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
