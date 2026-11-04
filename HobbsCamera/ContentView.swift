// ContentView.swift
import SwiftUI
import SwiftData
import UIKit
import CoreLocation

struct ContentView: View {
    var body: some View {
        NavigationStack {
            LibraryView()
        }
        .preferredColorScheme(.dark)
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// Most recent first.
    @Query(sort: \PhotoRecord.createdAt, order: .reverse)
    private var photos: [PhotoRecord]

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    @State private var isSelecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showingCamera = false

    @State private var lastErrorMessage: String?

    @StateObject private var photosExporter = PhotosExporter()
    @State private var showingExportSheet = false
    @State private var shareRequest: ShareRequest?

    /// Avoid multiple `.alert` modifiers fighting on device.
    @State private var activeAlert: ActiveAlert?

    private enum ActiveAlert: Identifiable, Equatable {
        case deleteConfirmation(count: Int)
        case confirmPhotosExport
        case photosPermission
        case exportFinished(message: String)
        case notice(title: String, message: String)
        case error(message: String)

        var id: String {
            switch self {
            case .deleteConfirmation(let count):
                return "deleteConfirmation_\(count)"
            case .confirmPhotosExport:
                return "confirmPhotosExport"
            case .photosPermission:
                return "photosPermission"
            case .notice(let title, let message):
                return "notice_\(title)_\(message)"
            case .exportFinished(let message):
                return "exportFinished_\(message)"
            case .error(let message):
                return "error_\(message)"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            if photos.isEmpty {
                emptyState
            } else {
                photoGrid
            }

            bottomControls
        }
        .navigationTitle(isSelecting ? selectionTitle : "Library")
        .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        setSelecting(false)
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            selectedIDs = Set(photos.map { $0.id })
                        } label: {
                            Label("Select All", systemImage: "checkmark.circle")
                        }

                        Menu {
                            ForEach(RetentionPeriod.allCases) { period in
                                Button(period.label) {
                                    selectOlder(than: period)
                                }
                            }
                        } label: {
                            Label("Older Than", systemImage: "calendar.badge.clock")
                        }

                        Button {
                            selectedIDs.removeAll()
                        } label: {
                            Label("Clear Selection", systemImage: "xmark.circle")
                        }
                        .disabled(selectedIDs.isEmpty)
                    } label: {
                        Label("Choose", systemImage: "ellipsis.circle")
                    }
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select") {
                        setSelecting(true)
                    }
                    .disabled(photos.isEmpty)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView()
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportProgressView(exporter: photosExporter) {
                showingExportSheet = false
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $shareRequest) { request in
            ShareSheet(urls: request.urls)
        }
        .task {
            #if DEBUG
            SampleData.loadIfRequested(into: modelContext)
            #endif
            runAutoDelete()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                runAutoDelete()
            }
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

            case .confirmPhotosExport:
                return Alert(
                    title: Text("Save to Apple Photos?"),
                    message: Text("Photos saved here leave HobbsCamera’s private storage. If Google Photos backup is on, they may be uploaded automatically. To avoid that, use Share instead."),
                    primaryButton: .default(Text("Save to Photos")) {
                        startExportSelectedToApplePhotos()
                    },
                    secondaryButton: .cancel()
                )

            case .notice(let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .cancel(Text("OK"))
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

    // MARK: - Content

    private var photoGrid: some View {
        ScrollView {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                Text("\(photos.count) \(photos.count == 1 ? "photo" : "photos") · Private to this app")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedDays, id: \.day) { group in
                    Section {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(group.records) { record in
                                gridItem(for: record)
                            }
                        }
                        .padding(.bottom, 20)
                    } header: {
                        dayHeader(for: group)
                    }
                }
            }
            .padding(.bottom, 140)
        }
    }

    @ViewBuilder
    private func gridItem(for record: PhotoRecord) -> some View {
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

    private func dayHeader(for group: DayGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(dayTitle(for: group.day))
                .font(.headline)
            Spacer()
            Text("\(group.records.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .background(Theme.background.opacity(0.92))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 112, height: 112)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text("No photos yet")
                    .font(.title2.weight(.semibold))
                Text("Snap your Hobbs, tach and fuel receipts. Each photo keeps its time and location, and stays private to this app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 120)
    }

    @ViewBuilder
    private var bottomControls: some View {
        if isSelecting {
            selectionBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            ShutterButton {
                showingCamera = true
            }
            .accessibilityLabel("Open camera")
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .transition(.opacity)
        }
    }

    private var selectionBar: some View {
        let hasSelection = !selectedIDs.isEmpty

        return HStack(spacing: 0) {
            selectionAction("Share", systemImage: "square.and.arrow.up") {
                shareSelected()
            }
            selectionAction("Photos", systemImage: "photo.badge.arrow.down") {
                activeAlert = .confirmPhotosExport
            }
            selectionAction("Delete", systemImage: "trash", tint: Theme.danger) {
                activeAlert = .deleteConfirmation(count: selectedIDs.count)
            }
        }
        .disabled(!hasSelection)
        .opacity(hasSelection ? 1 : 0.45)
        .padding(.vertical, 10)
        .glassCapsule()
    }

    private func selectionAction(
        _ title: String,
        systemImage: String,
        tint: Color = .primary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .medium))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel(title == "Photos" ? "Save to Apple Photos" : title)
    }

    private var selectionTitle: String {
        selectedIDs.isEmpty ? "Select Photos" : "\(selectedIDs.count) Selected"
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

    private func dayTitle(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }

        let sameYear = calendar.isDate(day, equalTo: Date(), toGranularity: .year)
        return day.formatted(
            sameYear
                ? .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                : .dateTime.month(.abbreviated).day().year()
        )
    }

    // MARK: - Selection

    private func setSelecting(_ selecting: Bool) {
        withAnimation(.snappy) {
            isSelecting = selecting
            if !selecting {
                selectedIDs.removeAll()
            }
        }
    }

    private func toggleSelection(for record: PhotoRecord) {
        if selectedIDs.contains(record.id) {
            selectedIDs.remove(record.id)
        } else {
            selectedIDs.insert(record.id)
        }
    }

    private func selectOlder(than period: RetentionPeriod) {
        let matches = PhotoRetention.olderThan(period, in: photos)
        if matches.isEmpty {
            activeAlert = .notice(
                title: "No matching photos",
                message: "No photos are older than \(period.label). Photos marked Keep aren’t included."
            )
        } else {
            selectedIDs = Set(matches.map { $0.id })
        }
    }

    // MARK: - Share

    private func shareSelected() {
        let selected = photos.filter { selectedIDs.contains($0.id) }
        let urls = selected.compactMap { $0.photoURL }

        if urls.count == selected.count {
            shareRequest = ShareRequest(urls: urls)
        } else {
            lastErrorMessage = "Couldn’t find the file for \(selected.count - urls.count) of the selected photos."
        }
    }

    // MARK: - Delete

    private func deleteSelected() {
        let idsToDelete = selectedIDs
        guard !idsToDelete.isEmpty else { return }

        let recordsToDelete = photos.filter { idsToDelete.contains($0.id) }

        do {
            try PhotoRetention.delete(recordsToDelete, in: modelContext)
            setSelecting(false)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func runAutoDelete() {
        let deletedIDs = PhotoRetention.runAutoDeleteIfEnabled(in: modelContext)
        guard !deletedIDs.isEmpty else { return }

        selectedIDs.subtract(deletedIDs)
        activeAlert = .notice(
            title: "Old photos deleted",
            message: "Auto-delete removed \(deletedIDs.count) \(deletedIDs.count == 1 ? "photo" : "photos"). You can change this in Settings."
        )
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
            var locations: [UUID: CLLocation] = [:]

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
                locations[record.id] = record.clLocation
            }

            showingExportSheet = true
            await photosExporter.exportToApplePhotos(
                items: validItems,
                initialFailures: initialFailures,
                locationProvider: { locations[$0.id] }
            )
        }
    }
}

/// A single thumbnail cell for the library grid.
private struct ThumbnailCell: View {
    let record: PhotoRecord

    var isSelected: Bool = false
    var showsSelectionChrome: Bool = false

    var body: some View {
        // The square sets the cell's size, so a photo of any shape fills it and is cropped to fit.
        Rectangle()
            .fill(Theme.card)
            .aspectRatio(1.0, contentMode: .fit)
            .overlay {
                FileImageView(url: record.thumbnailURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    ProgressView()
                }
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 36)
            }
            .clipped()
            .overlay(alignment: .bottomLeading) {
                Text(record.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                .padding(6)
            }
            .overlay(alignment: .bottomTrailing) {
                if record.isKept {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .accessibilityLabel("Kept")
                }
            }
            .overlay {
                if showsSelectionChrome && isSelected {
                    Rectangle()
                        .fill(.white.opacity(0.18))
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsSelectionChrome {
                    ZStack {
                        Circle()
                            .fill(isSelected ? Color.accentColor : .black.opacity(0.25))
                        Circle()
                            .strokeBorder(.white, lineWidth: 1.5)
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel("Photo taken \(record.createdAt.formatted(date: .abbreviated, time: .shortened))")
    }
}

struct PhotoDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let record: PhotoRecord

    @State private var shareRequest: ShareRequest?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FileImageView(url: record.photoURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } placeholder: {
                    Rectangle()
                        .fill(Theme.card)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .overlay { ProgressView() }
                }

                VStack(alignment: .leading, spacing: 16) {
                    PhotoMetadataView(record: record)

                    Toggle(isOn: keepBinding) {
                        HStack(spacing: 12) {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(record.isKept ? Color.accentColor : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Keep")
                                    .font(.body.weight(.semibold))
                                Text("Never auto-deleted or included in “older than” selection.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .card()
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(record.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let url = record.photoURL {
                        shareRequest = ShareRequest(urls: [url])
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(record.photoURL == nil)
            }
        }
        .sheet(item: $shareRequest) { request in
            ShareSheet(urls: request.urls)
        }
    }

    private var keepBinding: Binding<Bool> {
        Binding(
            get: { record.isKept },
            set: { newValue in
                record.isKept = newValue
                try? modelContext.save()
            }
        )
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

        // Read and decode off the main thread so scrolling and full-size photos stay smooth.
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)?.preparingForDisplay()
        }.value

        if let image {
            uiImage = image
        } else {
            loadError = "Failed to load image."
        }
    }
}
