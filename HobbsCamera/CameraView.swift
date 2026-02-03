import SwiftUI
import SwiftData

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var camera = CameraService()

    @State private var isCapturing = false
    @State private var showSavedOverlay = false

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
                }
                .padding()

                Spacer()

                VStack(spacing: 10) {
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
            if showSavedOverlay {
                Text("Saved!")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.65), in: Capsule())
                    .transition(.opacity.combined(with: .scale))
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showSavedOverlay)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func captureAndReturnToLibrary() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            // Capture jpeg bytes + timestamp (Phase 1)
            let capture = try await camera.capturePhoto()

            // Persist full-res + thumbnail, and create SwiftData record (Phase 1/2)
            let record = try await pipeline.run(capture: capture)

            // Save record (Phase 2)
            modelContext.insert(record)
            try modelContext.save()

            // Show "Saved!" briefly, then immediately return to library.
            showSavedOverlay = true

            // Small delay so the user actually sees "Saved!" before dismissing.
            // This still feels immediate, but is visible.
            try? await Task.sleep(nanoseconds: 350_000_000)

            dismiss()
        } catch {
            camera.lastErrorMessage = "Capture failed: \(error.localizedDescription)"
        }
    }
}
