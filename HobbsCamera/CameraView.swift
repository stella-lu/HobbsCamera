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
    @State private var showFlash = false
    @State private var savedFix: LocationFix?

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

            if let savedFix {
                savedToast(for: savedFix)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.2), value: savedFix)
        .animation(.easeOut(duration: 0.12), value: showFlash)
        .animation(.easeOut(duration: 0.2), value: isWaitingForLocation)
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
            locationPill
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if isWaitingForLocation {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text("Getting location…")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassCapsule()
                .transition(.opacity)
            }

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

    @ViewBuilder
    private var locationPill: some View {
        switch location.signal {
        case .searching:
            pill("GPS", detail: "Searching", color: .white.opacity(0.7), pulsing: true)
        case .fix(let accuracyMeters):
            pill(
                "GPS",
                detail: PhotoMetadataFormat.accuracy(meters: accuracyMeters),
                color: accuracyMeters <= LocationFixPolicy.goodAccuracyMeters ? Theme.live : Theme.caution
            )
        case .approximateOnly:
            settingsPill("Approximate")
        case .denied:
            settingsPill("Location off")
        }
    }

    private func pill(_ title: String, detail: String, color: Color, pulsing: Bool = false) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color, radius: 3)
                .opacity(pulsing ? 0.6 : 1)
            Text(title)
                .font(.footnote.weight(.bold))
            Text(detail)
                .font(.footnote.weight(.medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .glassCapsule()
    }

    private func settingsPill(_ text: String) -> some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "location.slash.fill")
                    .foregroundStyle(Theme.caution)
                Text(text)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 38)
            .glassCapsule()
        }
        .accessibilityHint("Opens Settings to allow precise location")
    }

    // MARK: - Saved toast

    private func savedToast(for fix: LocationFix) -> some View {
        let isLive = fix.status == .live
        let title: String
        let detail: String
        switch fix.status {
        case .live:
            title = "Saved"
            detail = "Time and location recorded"
        case .lastKnown:
            title = "Saved"
            detail = "Using last known location"
        case .unavailable, .denied:
            title = "Saved without location"
            detail = "Time recorded"
        }

        return VStack(spacing: 8) {
            Image(systemName: isLive ? "checkmark.circle.fill" : "location.slash.fill")
                .font(.system(size: 34))
                .foregroundStyle(isLive ? Theme.live : Theme.caution)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
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
            savedFix = locationFix
            let overlayNanoseconds: UInt64 = locationFix.status == .live ? 600_000_000 : 1_600_000_000
            try? await Task.sleep(nanoseconds: overlayNanoseconds)

            dismiss()
        } catch {
            isWaitingForLocation = false
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
