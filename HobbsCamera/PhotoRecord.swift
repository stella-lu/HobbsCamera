import CoreLocation
import Foundation
import SwiftData

/// Local persisted record for a captured photo.
///
/// Persistence strategy (important):
/// - `filePath` and `thumbnailPath` now store *portable identifiers* (filenames) for new records.
///   Example: "A1B2C3.jpg" and "A1B2C3_thumb.jpg"
///
/// Backward compatibility:
/// - Older records may contain absolute sandbox paths.
/// - We resolve URLs robustly by:
///   1) If the stored string is an absolute path and the file exists, use it.
///   2) Otherwise, treat it as a filename and resolve within AppPhotoStore directories.
///   3) If still missing, fall back to `lastPathComponent` resolved into the directory.
/// This prevents "Failed to load image" when sandbox container paths change in development.
@Model
final class PhotoRecord {
    /// Unique identifier for the record.
    @Attribute(.unique) var id: UUID

    /// For new records: filename only (portable).
    /// For old records: may be an absolute path.
    var filePath: String

    /// Capture time (source of truth for UI metadata display).
    var createdAt: Date

    /// For new records: thumbnail filename only (portable).
    /// For old records: may be an absolute path.
    var thumbnailPath: String

    /// Simple flags for future needs (favorite, exported, etc.).
    /// Stored as an integer bitmask to stay lightweight.
    var flags: Int

    // Location and time zone at capture.
    // All optional, so photos saved before these existed migrate automatically and read as nil.

    var latitude: Double?
    var longitude: Double?

    /// Radius of uncertainty in meters.
    var horizontalAccuracy: Double?

    /// Meters above mean sea level.
    var altitude: Double?
    var verticalAccuracy: Double?

    /// When the location fix was determined. This can differ from `createdAt`.
    var locationTimestamp: Date?

    /// Raw value of `LocationStatus`. Nil for photos saved before location was recorded.
    var locationStatusRaw: String?

    /// Time zone of the phone at capture, so local time stays correct after travelling.
    var captureTimeZoneIdentifier: String?

    init(
        id: UUID = UUID(),
        filePath: String,
        createdAt: Date,
        thumbnailPath: String,
        flags: Int = 0,
        locationFix: LocationFix? = nil,
        captureTimeZoneIdentifier: String? = nil
    ) {
        self.id = id
        self.filePath = filePath
        self.createdAt = createdAt
        self.thumbnailPath = thumbnailPath
        self.flags = flags
        self.latitude = locationFix?.location?.latitude
        self.longitude = locationFix?.location?.longitude
        self.horizontalAccuracy = locationFix?.location?.horizontalAccuracy
        self.altitude = locationFix?.location?.altitude
        self.verticalAccuracy = locationFix?.location?.verticalAccuracy
        self.locationTimestamp = locationFix?.location?.timestamp
        self.locationStatusRaw = locationFix?.status.rawValue
        self.captureTimeZoneIdentifier = captureTimeZoneIdentifier
    }
}

// MARK: - URL Resolution

extension PhotoRecord {
    /// Resolved URL for the full-resolution photo.
    /// Handles both new (filename) and legacy (absolute path) formats.
    var photoURL: URL? {
        AppPhotoStore.resolvePhotoURL(from: filePath)
    }

    /// Resolved URL for the thumbnail image.
    /// Handles both new (filename) and legacy (absolute path) formats.
    var thumbnailURL: URL? {
        AppPhotoStore.resolveThumbnailURL(from: thumbnailPath)
    }
}

// MARK: - Metadata

extension PhotoRecord {
    private static let keepFlag = 1 << 0

    /// A kept photo is never selected or deleted by age.
    var isKept: Bool {
        get { flags & Self.keepFlag != 0 }
        set { flags = newValue ? flags | Self.keepFlag : flags & ~Self.keepFlag }
    }

    var locationStatus: LocationStatus? {
        locationStatusRaw.flatMap(LocationStatus.init(rawValue:))
    }

    var captureTimeZone: TimeZone {
        captureTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// The location for Apple Photos, including the fix's own accuracy and time.
    var clLocation: CLLocation? {
        guard let latitude, let longitude else { return nil }
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude ?? 0,
            horizontalAccuracy: horizontalAccuracy ?? -1,
            verticalAccuracy: verticalAccuracy ?? -1,
            timestamp: locationTimestamp ?? createdAt
        )
    }

    var mapsURL: URL? {
        guard let latitude, let longitude else { return nil }
        return URL(string: "https://maps.apple.com/?ll=\(latitude),\(longitude)&q=\(latitude),\(longitude)")
    }
}
