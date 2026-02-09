import SwiftUI

struct ExportProgressView: View {
    @ObservedObject var exporter: PhotosExporter
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let message = exporter.lastSummaryMessage {
                    Section {
                        Text(message)
                            .font(.body)
                    }
                }

                if exporter.isExporting {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Saving to Apple Photos…")
                        }
                    }
                }

                Section("Results") {
                    ForEach(exporter.results) { r in
                        HStack(spacing: 12) {
                            statusIcon(for: r.status)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.filename)
                                    .lineLimit(1)
                                statusText(for: r.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Export")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        onDone()
                    }
                    .disabled(exporter.isExporting)
                }
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: PhotoExportResult.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func statusText(for status: PhotoExportResult.Status) -> some View {
        switch status {
        case .pending:
            Text("Pending")
        case .success:
            Text("Saved")
        case .failure(let message):
            Text(message)
        }
    }
}
