import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationTitle("Library")
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext

    /// Most recent first.
    @Query(sort: \PhotoRecord.createdAt, order: .reverse)
    private var photos: [PhotoRecord]

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        Group {
            if photos.isEmpty {
                ContentUnavailableView(
                    "No photos yet",
                    systemImage: "camera",
                    description: Text("Photos stay inside this app unless you export them.")
                )
                .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(photos) { record in
                            NavigationLink {
                                PhotoDetailView(record: record)
                            } label: {
                                ThumbnailCell(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    CameraView()
                        .navigationBarBackButtonHidden(true)
                } label: {
                    Label("Camera", systemImage: "camera.fill")
                }
            }
        }
    }
}

/// A single thumbnail cell for the library grid.
private struct ThumbnailCell: View {
    let record: PhotoRecord

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)

            FileImageView(url: record.thumbnailURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .aspectRatio(1.0, contentMode: .fit)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Photo taken \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
    }
}

struct PhotoDetailView: View {
    let record: PhotoRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                FileImageView(url: record.photoURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } placeholder: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.quaternary)
                        ProgressView()
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1.0, contentMode: .fit)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Timestamp")
                        .font(.headline)

                    Text(record.createdAt.formatted(date: .long, time: .standard))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
            }
            .padding()
        }
        .navigationTitle("Photo")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Loads a local file URL into a SwiftUI `Image` without blocking the main thread.
/// This is intentionally small and focused - it’s used for thumbnails and full-res images.
private struct FileImageView<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var loadError: String?

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(loadError)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                placeholder()
                    .task { await load() }
            }
        }
    }

    private func load() async {
        guard uiImage == nil else { return }
        guard let url else {
            loadError = "Missing file URL."
            return
        }

        do {
            let data = try Data(contentsOf: url)
            guard let image = UIImage(data: data) else {
                loadError = "Failed to decode image."
                return
            }
            uiImage = image
        } catch {
            loadError = "Failed to load image."
        }
    }
}
