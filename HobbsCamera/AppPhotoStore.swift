// AppPhotoStore.swift
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

    /// Minimum free space required to attempt saving a new photo.
    ///
    /// This is intentionally conservative - iOS can become unstable when a device is very low on storage,
    /// and writes may fail in ways that are hard to recover from gracefully.
    private static let minimumFreeBytesBeforeSave: Int64 = 200 * 1024 * 1024 // 200 MB

    /// Extra headroom beyond the estimated write size.
    /// This accounts for filesystem overhead, temporary allocations, and thumbnail generation.
    private static let saveHeadroomBytes: Int64 = 50 * 1024 * 1024 // 50 MB

    // MARK: - Public API (Save)

    /// Saves the photo to private storage, stamps timestamp metadata, and returns the saved photo URL.
    /// New code should store `url.lastPathComponent` (the filename) in SwiftData, not the absolute path.
    static func saveJPEGToPrivateLibrary(_ jpegData: Data, createdAt: Date) throws -> URL {
        // Phase 4: guard against low-storage writes before touching disk.
        // We include a small estimate for the thumbnail too.
        try assertEnoughDiskSpaceForSave(estimatedWriteBytes: Int64(jpegData.count) + 1_200_000)

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

    // MARK: - Public API (Storage)

    struct StorageUsage: Equatable {
        let photosBytes: Int64
        let thumbnailsBytes: Int64
        let appTotalBytes: Int64
        let deviceAvailableBytes: Int64?
        let deviceTotalBytes: Int64?
    }

    /// Returns best-effort storage usage info for the app and the device.
    static func currentStorageUsage() throws -> StorageUsage {
        let photosDir = try photosDirectoryURL()
        let thumbsDir = try thumbnailsDirectoryURL()

        let photosBytes = directorySizeBytes(at: photosDir)
        let thumbnailsBytes = directorySizeBytes(at: thumbsDir)
        let appTotal = photosBytes + thumbnailsBytes

        let device = deviceCapacityBytes()

        return StorageUsage(
            photosBytes: photosBytes,
            thumbnailsBytes: thumbnailsBytes,
            appTotalBytes: appTotal,
            deviceAvailableBytes: device.available,
            deviceTotalBytes: device.total
        )
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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

    // MARK: - Public API (Delete)

    /// Deletes a photo file and its thumbnail (if present) from private storage.
    ///
    /// This is best-effort: missing files are ignored.
    static func deletePhotoAndThumbnail(photoStoredValue: String, thumbnailStoredValue: String) throws {
        try deleteFileIfPresent(url: resolvePhotoURL(from: photoStoredValue))
        try deleteFileIfPresent(url: resolveThumbnailURL(from: thumbnailStoredValue))
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

    // MARK: - Private (Delete Helpers)

    private static func deleteFileIfPresent(url: URL?) throws {
        guard let url else { return }

        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            do {
                try fm.removeItem(at: url)
            } catch {
                // If the file disappears between the exists check and remove, treat as fine.
                if fm.fileExists(atPath: url.path) {
                    throw error
                }
            }
        }
    }

    // MARK: - Private (Storage Checks)

    /// Throws a user-friendly error if the device does not have enough free space for the save.
    private static func assertEnoughDiskSpaceForSave(estimatedWriteBytes: Int64) throws {
        let device = deviceCapacityBytes()
        guard let available = device.available else {
            // If we can't read capacity, proceed - writes can still fail, and the UI will surface the error.
            return
        }

        let required = max(minimumFreeBytesBeforeSave, estimatedWriteBytes + saveHeadroomBytes)
        if available < required {
            throw StoreError.lowDiskSpace(availableBytes: available, requiredBytes: required)
        }
    }

    private static func deviceCapacityBytes() -> (available: Int64?, total: Int64?) {
        // Using the home directory is sufficient to query the current volume.
        let url = URL(fileURLWithPath: NSHomeDirectory())
        do {
            let values = try url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey,
                .volumeTotalCapacityKey
            ])

            // NOTE: On some SDKs these properties are Int?, not Int64?, so we normalize to Int64 here.
            let availableImportant: Int64? = values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
            let availableRegular: Int64? = values.volumeAvailableCapacity.map { Int64($0) }
            let available = availableImportant ?? availableRegular

            let total: Int64? = values.volumeTotalCapacity.map { Int64($0) }

            return (available: available, total: total)
        } catch {
            return (available: nil, total: nil)
        }
    }

    private static func directorySizeBytes(at directoryURL: URL) -> Int64 {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]

        guard let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: Array(keys)) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            guard values.isRegularFile == true else { continue }
            if let size = values.fileSize {
                total += Int64(size)
            }
        }

        return total
    }
}

// MARK: - Errors

enum StoreError: Error {
    case thumbnailGenerationFailed
    case metadataStampingFailed
    case lowDiskSpace(availableBytes: Int64, requiredBytes: Int64)
}

extension StoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .thumbnailGenerationFailed:
            return "Could not generate thumbnail."
        case .metadataStampingFailed:
            return "Could not save photo metadata."
        case let .lowDiskSpace(availableBytes, requiredBytes):
            let available = AppPhotoStore.formatBytes(availableBytes)
            let required = AppPhotoStore.formatBytes(requiredBytes)

            return "Low storage. HobbsCamera needs about \(required) free to save a photo, but your device only has \(available) available. Free up space in Settings - General - iPhone Storage, delete some photos in HobbsCamera, then try again."
        }
    }
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
