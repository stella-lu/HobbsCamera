import SwiftUI

struct CameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraService()

    @State private var isCapturing = false
    @State private var lastSavedURL: URL? = nil
    @State private var showSavedToast = false

    var body: some View {
        ZStack {
            // Preview
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            // Overlay UI
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Spacer()

                    if let msg = camera.lastErrorMessage {
                        Text(msg)
                            .font(.footnote)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()

                Spacer()

                // Bottom controls
                VStack(spacing: 12) {
                    if let url = lastSavedURL {
                        Text("Saved privately: \(url.lastPathComponent)")
                            .font(.footnote)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        Task {
                            await capture()
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 76, height: 76)
                            Circle()
                                .strokeBorder(.white.opacity(0.6), lineWidth: 6)
                                .frame(width: 88, height: 88)
                        }
                    }
                    .disabled(isCapturing || camera.lastErrorMessage != nil)
                    .padding(.bottom, 30)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            camera.start()
        }
        .onDisappear {
            camera.stop()
        }
    }

    private func capture() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }

        do {
            let url = try await camera.capturePhoto()
            lastSavedURL = url
        } catch {
            camera.lastErrorMessage = "Capture failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    NavigationStack { CameraView() }
}
