// CameraView.swift
import SwiftUI
import SwiftData
import UIKit

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var camera = CameraService()
    @StateObject private var location = LocationService()

    @State private var isCapturing = false
    @State private var isWaitingForLocation = false
    @State private var savedOverlayMessage: String?

    private let pipeline = PhotoSavePipeline()

    var body: some View {
        ZStack {
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Top bar + bottom capture button
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Spacer()

                    locationBadge
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
                    if isWaitingForLocation {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Getting location…")
                        }
                        .font(.callout)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                    }

                    if let error = camera.lastErrorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.6), in: Capsule())
                    }

                    Button {
                        Task { await captureAndReturnToLibrary() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 72, height: 72)

                            Circle()
                                .stroke(.black.opacity(0.2), lineWidth: 2)
                                .frame(width: 72, height: 72)

                            if isCapturing {
                                ProgressView()
                                    .tint(.black)
                            }
                        }
                    }
                    .disabled(isCapturing)
                    .padding(.bottom, 28)
                    .accessibilityLabel("Capture photo")
                }
            }

            // Center "Saved!" overlay
            if let savedOverlayMessage {
                Text(savedOverlayMessage)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.65), in: Capsule())
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: savedOverlayMessage)
        .onAppear {
            camera.start()
            location.start()
        }
        .onDisappear {
            camera.stop()
            location.stop()
        }
    }

    @ViewBuilder
    private var locationBadge: some View {
        switch location.signal {
        case .searching:
            badge("Searching for GPS", systemImage: "location.magnifyingglass", color: .white)
        case .fix(let accuracyMeters):
            badge(
                PhotoMetadataFormat.accuracy(meters: accuracyMeters),
                systemImage: "location.fill",
                color: accuracyMeters <= LocationFixPolicy.goodAccuracyMeters ? .green : .orange
            )
        case .approximateOnly:
            settingsBadge("Precise Location off")
        case .denied:
            settingsBadge("Location off")
        }
    }

    private func badge(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.6), in: Capsule())
    }

    private func settingsBadge(_ text: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            badge("\(text) - Fix", systemImage: "location.slash.fill", color: .orange)
        }
    }

    private func savedMessage(for fix: LocationFix) -> String {
        switch fix.status {
        case .live:
            return "Saved!"
        case .lastKnown:
            return "Saved with last known location"
        case .unavailable, .denied:
            return "Saved without location"
        }
    }

    private func captureAndReturnToLibrary() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            // Capture jpeg bytes + timestamp (Phase 1)
            let capture = try await camera.capturePhoto()

            // Find the location, waiting briefly if needed. The capture time is already fixed.
            isWaitingForLocation = true
            let locationFix = await location.fix(forCaptureAt: capture.createdAt)
            isWaitingForLocation = false

            // Persist full-res + thumbnail, and create SwiftData record (Phase 1/2)
            let record = try await pipeline.run(capture: capture, locationFix: locationFix)

            // Save record (Phase 2)
            modelContext.insert(record)
            try modelContext.save()

            // Confirm briefly, then return to library. A photo without a current location stays up longer so it's noticed.
            savedOverlayMessage = savedMessage(for: locationFix)
            let overlayNanoseconds: UInt64 = locationFix.status == .live ? 350_000_000 : 1_500_000_000
            try? await Task.sleep(nanoseconds: overlayNanoseconds)

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
}
