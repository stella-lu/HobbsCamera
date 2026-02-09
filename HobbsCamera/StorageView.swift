// StorageView.swift
import SwiftUI

struct StorageView: View {
    @State private var isLoading = false
    @State private var usage: AppPhotoStore.StorageUsage?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let usage {
                Section("HobbsCamera") {
                    LabeledContent("Photos") {
                        Text(AppPhotoStore.formatBytes(usage.photosBytes))
                    }
                    LabeledContent("Thumbnails") {
                        Text(AppPhotoStore.formatBytes(usage.thumbnailsBytes))
                    }
                    LabeledContent("Total") {
                        Text(AppPhotoStore.formatBytes(usage.appTotalBytes))
                            .fontWeight(.semibold)
                    }
                }

                Section("Device") {
                    LabeledContent("Available") {
                        if let available = usage.deviceAvailableBytes {
                            Text(AppPhotoStore.formatBytes(available))
                        } else {
                            Text("Unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Total") {
                        if let total = usage.deviceTotalBytes {
                            Text(AppPhotoStore.formatBytes(total))
                        } else {
                            Text("Unavailable")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Text("If saves fail, free up space in Settings - General - iPhone Storage, then try again.")
                        .foregroundStyle(.secondary)
                }
            } else if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else {
                Section {
                    ContentUnavailableView(
                        "Couldn’t load storage info",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage ?? "Try again.")
                    )
                }
            }
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task {
            await reload()
        }
    }

    private func reload() async {
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await Task.detached(priority: .utility) {
                try AppPhotoStore.currentStorageUsage()
            }.value

            usage = result
            errorMessage = nil
        } catch {
            usage = nil
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        StorageView()
    }
}
