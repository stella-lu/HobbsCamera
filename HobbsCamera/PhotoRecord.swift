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

    init(
        id: UUID = UUID(),
        filePath: String,
        createdAt: Date,
        thumbnailPath: String,
        flags: Int = 0
    ) {
        self.id = id
        self.filePath = filePath
        self.createdAt = createdAt
        self.thumbnailPath = thumbnailPath
        self.flags = flags
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
