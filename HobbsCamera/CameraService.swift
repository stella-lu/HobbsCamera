import AVFoundation
import Foundation

@MainActor
final class CameraService: NSObject, ObservableObject {
    // Public
    @Published var isRunning: Bool = false
    @Published var lastErrorMessage: String? = nil

    let session = AVCaptureSession()

    // Private
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let photoOutput = AVCapturePhotoOutput()

    private var isConfigured = false

    func start() {
        lastErrorMessage = nil

        // Request permission first
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartIfNeeded()
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    configureAndStartIfNeeded()
                } else {
                    lastErrorMessage = "Camera permission is required to take photos."
                }
            }
        default:
            lastErrorMessage = "Camera permission is disabled. Enable it in Settings."
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            Task { @MainActor in
                self.isRunning = false
            }
        }
    }

    func capturePhoto() async throws -> URL {
        // Capture returns JPEG data, and we save it privately in the app sandbox.
        let data = try await captureJPEGData()
        let url = try AppPhotoStore.saveJPEGToPrivateLibrary(data: data)
        return url
    }

    // MARK: - Configuration

    private func configureAndStartIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            if !self.isConfigured {
                do {
                    try self.configureSession()
                    self.isConfigured = true
                } catch {
                    Task { @MainActor in
                        self.lastErrorMessage = "Failed to configure camera: \(error.localizedDescription)"
                    }
                    return
                }
            }

            if !self.session.isRunning {
                self.session.startRunning()
            }

            Task { @MainActor in
                self.isRunning = true
            }
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else {
            throw NSError(domain: "CameraService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No back camera available."])
        }

        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        } else {
            throw NSError(domain: "CameraService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to add camera input."])
        }

        // Output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        } else {
            throw NSError(domain: "CameraService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to add photo output."])
        }

        session.commitConfiguration()
    }

    // MARK: - Capture

    private func captureJPEGData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])

            let delegate = PhotoCaptureDelegate { result in
                switch result {
                case .success(let data):
                    continuation.resume(returning: data)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            // Keep delegate alive until callback completes
            PhotoCaptureDelegateStore.shared.add(delegate)

            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

// MARK: - Delegate plumbing

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    typealias Completion = (Result<Data, Error>) -> Void
    private let completion: Completion

    init(completion: @escaping Completion) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        defer { PhotoCaptureDelegateStore.shared.remove(self) }

        if let error = error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(NSError(domain: "CameraService", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to get photo data."])))
            return
        }
        completion(.success(data))
    }
}

private final class PhotoCaptureDelegateStore {
    static let shared = PhotoCaptureDelegateStore()
    private init() {}

    private var delegates: Set<ObjectIdentifier> = []
    private var objects: [ObjectIdentifier: AnyObject] = [:]

    func add(_ obj: AnyObject) {
        let id = ObjectIdentifier(obj)
        delegates.insert(id)
        objects[id] = obj
    }

    func remove(_ obj: AnyObject) {
        let id = ObjectIdentifier(obj)
        delegates.remove(id)
        objects[id] = nil
    }
}
