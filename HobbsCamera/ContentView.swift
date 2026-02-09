// ContentView.swift
import SwiftUI
import SwiftData
import UIKit

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

    @State private var lastErrorMessage: String?

    @StateObject private var photosExporter = PhotosExporter()
    @State private var showingExportSheet = false

    /// Avoid multiple `.alert` modifiers fighting on device.
    @State private var activeAlert: ActiveAlert?

    private enum ActiveAlert: Identifiable, Equatable {
        case deleteConfirmation(count: Int)
        case photosPermission
        case exportFinished(message: String)
        case error(message: String)

        var id: String {
            switch self {
            case .deleteConfirmation(let count):
                return "deleteConfirmation_\(count)"
            case .photosPermission:
                return "photosPermission"
            case .exportFinished(let message):
                return "exportFinished_\(message)"
            case .error(let message):
                return "error_\(message)"
            }
        }
    }

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
        .navigationTitle(isSelecting ? "" : "Library")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .disabled(isSelecting)

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

                    Button {
                        startExportSelectedToApplePhotos()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(selectedIDs.isEmpty)

                    Button(role: .destructive) {
                        activeAlert = .deleteConfirmation(count: selectedIDs.count)
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
        .sheet(isPresented: $showingExportSheet) {
            ExportProgressView(exporter: photosExporter) {
                showingExportSheet = false
            }
            .presentationDetents([.medium, .large])
        }
        .onChange(of: photosExporter.lastSummaryMessage) { _, newValue in
            if let newValue {
                activeAlert = .exportFinished(message: newValue)
            }
        }
        .onChange(of: lastErrorMessage) { _, newValue in
            if let newValue {
                activeAlert = .error(message: newValue)
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .deleteConfirmation(let count):
                return Alert(
                    title: Text("Delete selected photos?"),
                    message: Text("This will delete \(count) selected \(count == 1 ? "photo" : "photos"). This is permanent. Are you sure?"),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteSelected()
                    },
                    secondaryButton: .cancel()
                )

            case .photosPermission:
                return Alert(
                    title: Text("Allow Photos Access"),
                    message: Text("To save photos to Apple Photos, allow Photos access. HobbsCamera requests add-only access, so it can save without reading your library."),
                    primaryButton: .default(Text("Open Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    },
                    secondaryButton: .cancel()
                )

            case .exportFinished(let message):
                return Alert(
                    title: Text("Export finished"),
                    message: Text(message),
                    dismissButton: .cancel(Text("OK")) {
                        photosExporter.lastSummaryMessage = nil
                    }
                )

            case .error(let message):
                return Alert(
                    title: Text("Something went wrong"),
                    message: Text(message),
                    dismissButton: .cancel(Text("OK")) {
                        lastErrorMessage = nil
                    }
                )
            }
        }
    }

    // MARK: - Grouping

    private struct DayGroup {
        let day: Date
        let records: [PhotoRecord]
    }

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

    // MARK: - Export

    private func startExportSelectedToApplePhotos() {
        let idsToExport = selectedIDs
        guard !idsToExport.isEmpty else { return }

        let recordsToExport = photos.filter { idsToExport.contains($0.id) }

        Task { @MainActor in
            let permission = await photosExporter.requestAddOnlyPermissionIfNeeded()
            guard permission == .allowed || permission == .limited else {
                activeAlert = .photosPermission
                return
            }

            var validItems: [ExportItem] = []
            var initialFailures: [PhotoExportResult] = []

            for record in recordsToExport {
                guard let url = record.photoURL else {
                    initialFailures.append(
                        PhotoExportResult(
                            id: record.id,
                            filename: URL(fileURLWithPath: record.filePath).lastPathComponent,
                            status: .failure(message: "Missing file URL.")
                        )
                    )
                    continue
                }

                // Pass the app’s source-of-truth timestamp to PhotosExporter
                // so Photos uses it for the asset’s displayed date.
                validItems.append(ExportItem(id: record.id, fileURL: url, createdAt: record.createdAt))
            }

            showingExportSheet = true
            await photosExporter.exportToApplePhotos(items: validItems, initialFailures: initialFailures)
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
