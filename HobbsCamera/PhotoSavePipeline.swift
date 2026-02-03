import Foundation

/// A lightweight, testable abstraction for:
/// capture -> process -> persist
///
/// Phase 1/2 responsibilities:
/// - Save full-res JPEG to private storage
/// - Ensure timestamp metadata is present
/// - Generate and save thumbnail
/// - Return a `PhotoRecord` ready to be inserted into SwiftData
struct PhotoSavePipeline {
    func run(capture: PhotoCapture) async throws -> PhotoRecord {
        try await Task.detached(priority: .userInitiated) {
            let photoURL = try AppPhotoStore.saveJPEGToPrivateLibrary(capture.jpegData, createdAt: capture.createdAt)
            let thumbURL = try AppPhotoStore.generateAndSaveThumbnail(for: photoURL)

            // Store portable identifiers (filenames), not absolute paths.
            return PhotoRecord(
                filePath: photoURL.lastPathComponent,
                createdAt: capture.createdAt,
                thumbnailPath: thumbURL.lastPathComponent,
                flags: 0
            )
        }.value
    }
}
