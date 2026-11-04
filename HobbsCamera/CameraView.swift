// CameraView.swift
import SwiftUI
import SwiftData

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var camera = CameraService()
    @State private var location = LocationService()

    @State private var isCapturing = false
    @State private var showFlash = false
    @State private var showSaved = false

    private let pipeline = PhotoSavePipeline()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomBar
            }

            if showFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if showSaved {
                savedToast
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: showSaved)
        .animation(.easeOut(duration: 0.12), value: showFlash)
        .onAppear {
            camera.start()
            location.start()
        }
        .onDisappear {
            camera.stop()
            location.stop()
        }
    }

    // MARK: - Bars

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .glassCapsule()
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel("Close camera")

            Spacer()

            utcClock
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if let error = camera.lastErrorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassCapsule()
                    .padding(.horizontal, 24)
            }

            ShutterButton(isBusy: isCapturing, size: 80) {
                Task { await captureAndReturnToLibrary() }
            }
            .disabled(isCapturing)
            .accessibilityLabel("Capture photo")
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 220)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// The time that will be recorded, in UTC, so it can be checked against the aircraft clock.
    private var utcClock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.clockFormatter.string(from: context.date) + "Z")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .glassCapsule()
        }
        .accessibilityLabel("UTC time")
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    // MARK: - Saved toast

    private var savedToast: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.live)
            Text("Saved")
                .font(.headline)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Capture

    private func captureAndReturnToLibrary() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            // Capture jpeg bytes + timestamp (Phase 1)
            let capture = try await camera.capturePhoto()
            flash()

            // Attach the current location if there is one. Without it the photo keeps its time only.
            let capturedLocation = location.location(forCaptureAt: capture.createdAt)

            // Persist full-res + thumbnail, and create SwiftData record (Phase 1/2)
            let record = try await pipeline.run(capture: capture, location: capturedLocation)

            // Save record (Phase 2)
            modelContext.insert(record)
            try modelContext.save()

            // Confirm briefly, then return to library.
            showSaved = true
            try? await Task.sleep(nanoseconds: 600_000_000)

            dismiss()
        } catch {
            if let storeError = error as? AppPhotoStore.StoreError {
                switch storeError {
                case .lowDiskSpace:
                    camera.lastErrorMessage = storeError.localizedDescription
                default:
                    camera.lastErrorMessage = "Capture failed: \(storeError.localizedDescription)"
                }
            } else {
                camera.lastErrorMessage = "Capture failed: \(error.localizedDescription)"
            }
        }
    }

    private func flash() {
        showFlash = true
        Task {
            try? await Task.sleep(nanoseconds: 90_000_000)
            showFlash = false
        }
    }
}
