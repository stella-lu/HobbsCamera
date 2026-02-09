import Foundation
import Photos
import CoreLocation

/// Minimal adapter for exporting a sandbox image file into Apple Photos.
struct ExportItem: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let filename: String
    let createdAt: Date

    init(id: UUID, fileURL: URL, createdAt: Date) {
        self.id = id
        self.fileURL = fileURL
        self.filename = fileURL.lastPathComponent
        self.createdAt = createdAt
    }
}

/// Per-photo export feedback for the UI.
struct PhotoExportResult: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case success
        case failure(message: String)
    }

    let id: UUID
    let filename: String
    var status: Status
}

@MainActor
final class PhotosExporter: ObservableObject {
    @Published var isExporting: Bool = false
    @Published var results: [PhotoExportResult] = []
    @Published var lastSummaryMessage: String? = nil

    enum PermissionState: Equatable {
        case unknown
        case allowed
        case denied
        case restricted
        case limited
    }

    func currentAddOnlyPermission() -> PermissionState {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized:
            return .allowed
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    func requestAddOnlyPermissionIfNeeded() async -> PermissionState {
        let existing = currentAddOnlyPermission()
        guard existing == .unknown else { return existing }

        let newStatus: PHAuthorizationStatus = await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                cont.resume(returning: status)
            }
        }

        switch newStatus {
        case .authorized:
            return .allowed
        case .limited:
            return .limited
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    /// Export the provided files into Apple Photos.
    /// - Parameters:
    ///   - items: Valid items with file URLs.
    ///   - initialFailures: Precomputed failures (e.g., missing file URLs) that should appear in the results list.
    ///   - locationProvider: Optional per-item location.
    func exportToApplePhotos(
        items: [ExportItem],
        initialFailures: [PhotoExportResult] = [],
        locationProvider: ((ExportItem) -> CLLocation?)? = nil
    ) async {
        lastSummaryMessage = nil

        let pending: [PhotoExportResult] = items.map {
            PhotoExportResult(id: $0.id, filename: $0.filename, status: .pending)
        }
        results = initialFailures + pending

        guard !items.isEmpty else {
            summarizeResults()
            return
        }

        isExporting = true
        defer { isExporting = false }

        for item in items {
            do {
                try await exportSingle(item: item, location: locationProvider?(item))
                updateResult(id: item.id, status: .success)
            } catch {
                updateResult(id: item.id, status: .failure(message: error.localizedDescription))
            }
        }

        summarizeResults()
    }

    private func exportSingle(item: ExportItem, location: CLLocation?) async throws {
        let fileURL = item.fileURL

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "PhotosExporter", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "File not found."
            ])
        }

        // Explicit continuation type fixes: "Generic parameter 'T' could not be inferred".
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                let createRequest = PHAssetCreationRequest.forAsset()

                // CRITICAL: force the asset "date taken" to match what our app shows.
                // This avoids Apple Photos interpreting embedded EXIF dates in the wrong timezone.
                createRequest.creationDate = item.createdAt

                if let location {
                    createRequest.location = location
                }

                let options = PHAssetResourceCreationOptions()
                options.originalFilename = item.filename

                // Keep embedded metadata as much as iOS allows, but do not rely on it for the visible timestamp.
                createRequest.addResource(with: .photo, fileURL: fileURL, options: options)
            }, completionHandler: { success, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }

                if success {
                    cont.resume(returning: ())
                } else {
                    cont.resume(throwing: NSError(domain: "PhotosExporter", code: 2, userInfo: [
                        NSLocalizedDescriptionKey: "Unknown export failure."
                    ]))
                }
            })
        }
    }

    private func updateResult(id: UUID, status: PhotoExportResult.Status) {
        if let idx = results.firstIndex(where: { $0.id == id }) {
            results[idx].status = status
        }
    }

    private func summarizeResults() {
        let successCount = results.filter {
            if case .success = $0.status { return true }
            return false
        }.count

        let failureCount = results.count - successCount

        if results.isEmpty {
            lastSummaryMessage = "No photos selected."
            return
        }

        if failureCount == 0 {
            lastSummaryMessage = "Saved \(successCount) photo(s) to Apple Photos."
        } else if successCount == 0 {
            lastSummaryMessage = "Failed to save \(failureCount) photo(s)."
        } else {
            lastSummaryMessage = "Saved \(successCount) photo(s). Failed \(failureCount)."
        }
    }
}
