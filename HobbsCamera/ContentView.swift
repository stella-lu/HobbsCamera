import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
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

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []

    @State private var showDeleteConfirmation = false
    @State private var lastErrorMessage: String?

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
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedDays, id: \.day) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(dayHeaderString(for: group.day))
                                    .font(.headline)
                                    .padding(.horizontal, 8)

                                LazyVGrid(columns: columns, spacing: 6) {
                                    ForEach(group.records) { record in
                                        if isSelecting {
                                            Button {
                                                toggleSelection(for: record)
                                            } label: {
                                                ThumbnailCell(
                                                    record: record,
                                                    isSelected: selectedIDs.contains(record.id),
                                                    showsSelectionChrome: true
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            NavigationLink {
                                                PhotoDetailView(record: record)
                                            } label: {
                                                ThumbnailCell(record: record)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        // Hide the "Library" header title while selecting.
        .navigationTitle(isSelecting ? "" : "Library")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(isSelecting ? "Done" : "Select") {
                    withAnimation(.snappy) {
                        isSelecting.toggle()
                        if !isSelecting {
                            selectedIDs.removeAll()
                        }
                    }
                }
                .disabled(photos.isEmpty)
            }

            if isSelecting {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Select all") {
                        selectedIDs = Set(photos.map { $0.id })
                    }
                    .disabled(photos.isEmpty)

                    Button("Clear") {
                        selectedIDs.removeAll()
                    }
                    .disabled(selectedIDs.isEmpty)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            } else {
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
        .alert("Delete selected photos?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete \(selectedCount) selected \(selectedCount == 1 ? "photo" : "photos"). This is permanent. Are you sure?")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { lastErrorMessage != nil },
            set: { if !$0 { lastErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lastErrorMessage ?? "")
        }
    }

    private var selectedCount: Int {
        selectedIDs.count
    }

    // MARK: - Grouping

    private struct DayGroup {
        let day: Date
        let records: [PhotoRecord]
    }

    /// Groups photos by the user's calendar day.
    /// - Sections: most recent day first
    /// - Within a day: most recent time first
    private var groupedDays: [DayGroup] {
        let calendar = Calendar.current

        let grouped = Dictionary(grouping: photos) { record in
            calendar.startOfDay(for: record.createdAt)
        }

        let sortedDays = grouped.keys.sorted(by: { $0 > $1 })

        return sortedDays.map { day in
            let records = (grouped[day] ?? []).sorted(by: { $0.createdAt > $1.createdAt })
            return DayGroup(day: day, records: records)
        }
    }

    private func dayHeaderString(for day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "EEEE MMMM d, yyyy"
        return formatter.string(from: day)
    }

    // MARK: - Selection

    private func toggleSelection(for record: PhotoRecord) {
        if selectedIDs.contains(record.id) {
            selectedIDs.remove(record.id)
        } else {
            selectedIDs.insert(record.id)
        }
    }

    // MARK: - Delete

    private func deleteSelected() {
        let idsToDelete = selectedIDs
        guard !idsToDelete.isEmpty else { return }

        let recordsToDelete = photos.filter { idsToDelete.contains($0.id) }

        do {
            for record in recordsToDelete {
                try AppPhotoStore.deletePhotoAndThumbnail(
                    photoStoredValue: record.filePath,
                    thumbnailStoredValue: record.thumbnailPath
                )
                modelContext.delete(record)
            }

            try modelContext.save()

            withAnimation(.snappy) {
                selectedIDs.removeAll()
                isSelecting = false
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

/// A single thumbnail cell for the library grid.
private struct ThumbnailCell: View {
    let record: PhotoRecord

    var isSelected: Bool = false
    var showsSelectionChrome: Bool = false

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

            if showsSelectionChrome {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .padding(6)
                    }
                    Spacer()
                }
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
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
