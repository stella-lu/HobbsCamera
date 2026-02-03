import AVFoundation
import Foundation

/// Camera service:
/// - Manages AVCaptureSession lifecycle
/// - Handles permission states and user messaging
/// - Captures photos asynchronously as JPEG bytes + capture timestamp
@MainActor
final class CameraService: ObservableObject {
    let session = AVCaptureSession()

    @Published var lastErrorMessage: String?

    private let sessionQueue = DispatchQueue(label: "com.hobbscamera.session.queue")
    private var isConfigured = false

    private var photoOutput = AVCapturePhotoOutput()

    func start() {
        lastErrorMessage = nil

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureIfNeededAndStart()
        case .notDetermined:
            requestPermissionAndStart()
        case .denied:
            lastErrorMessage = "Camera access is denied. Enable it in Settings to take photos."
        case .restricted:
            lastErrorMessage = "Camera access is restricted on this device."
        @unknown default:
            lastErrorMessage = "Unknown camera permission state."
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// Captures a photo and returns JPEG bytes plus a capture timestamp.
    /// The persistence pipeline (metadata stamping, saving files, thumbnails, records) happens elsewhere.
    func capturePhoto() async throws -> PhotoCapture {
        // Ensure session is running before capture.
        guard session.isRunning else {
            throw CameraError.sessionNotRunning
        }

        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true

        // Capturing time for metadata stamping.
        let createdAt = Date()

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate(createdAt: createdAt) { result in
                continuation.resume(with: result)
            }

            Task {
                await CaptureDelegateStore.shared.insert(delegate)
            }

            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    // MARK: - Permission + Configuration

    private func requestPermissionAndStart() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                if granted {
                    self.configureIfNeededAndStart()
                } else {
                    self.lastErrorMessage = "Camera access is required to take photos."
                }
            }
        }
    }

    private func configureIfNeededAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    DispatchQueue.main.async {
                        self.lastErrorMessage = "Failed to configure camera."
                    }
                    return
                }
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .photo

        defer { session.commitConfiguration() }

        // Input: back wide angle camera.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.noCameraDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        // Output: photo output.
        guard session.canAddOutput(photoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(photoOutput)

        photoOutput.isHighResolutionCaptureEnabled = true
    }
}

// MARK: - Types

struct PhotoCapture: Sendable {
    let jpegData: Data
    let createdAt: Date
}

enum CameraError: Error {
    case sessionNotRunning
    case noCameraDevice
    case cannotAddInput
    case cannotAddOutput
}

// MARK: - Delegate + Lifetime Management

/// AVCapturePhotoCaptureDelegate that captures JPEG bytes and returns them via callback.
/// Must be kept alive until the capture completes.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let createdAt: Date
    private let completion: (Result<PhotoCapture, Error>) -> Void
    private let id = UUID()

    init(createdAt: Date, completion: @escaping (Result<PhotoCapture, Error>) -> Void) {
        self.createdAt = createdAt
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }

        guard let data = photo.fileDataRepresentation() else {
            finish(.failure(NSError(domain: "CameraService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data."])))
            return
        }

        finish(.success(PhotoCapture(jpegData: data, createdAt: createdAt)))
    }

    private func finish(_ result: Result<PhotoCapture, Error>) {
        completion(result)
        Task {
            await CaptureDelegateStore.shared.remove(id: id)
        }
    }

    var delegateID: UUID { id }
}

/// Holds capture delegates strongly until capture completes.
private actor CaptureDelegateStore {
    static let shared = CaptureDelegateStore()
    private var delegates: [UUID: PhotoCaptureDelegate] = [:]

    func insert(_ delegate: PhotoCaptureDelegate) {
        delegates[delegate.delegateID] = delegate
    }

    func remove(id: UUID) {
        delegates[id] = nil
    }
}
