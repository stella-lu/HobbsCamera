// SettingsView.swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var photos: [PhotoRecord]

    @AppStorage(PhotoRetention.autoDeleteEnabledKey) private var autoDeleteEnabled = false
    @AppStorage(PhotoRetention.autoDeleteDaysKey) private var autoDeleteDays = PhotoRetention.defaultPeriod.rawValue

    /// A change that needs confirming because it could delete photos.
    @State private var pendingPeriod: RetentionPeriod?

    var body: some View {
        List {
            NavigationLink {
                StorageView()
            } label: {
                Label("Storage", systemImage: "internaldrive")
            }

            Section {
                Toggle("Auto-delete old photos", isOn: autoDeleteBinding)

                if autoDeleteEnabled {
                    Picker("Delete after", selection: periodBinding) {
                        ForEach(RetentionPeriod.allCases) { period in
                            Text(period.label).tag(period)
                        }
                    }
                }
            } header: {
                Text("Old photos")
            } footer: {
                Text(autoDeleteFooter)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Auto-delete photos?",
            isPresented: Binding(
                get: { pendingPeriod != nil },
                set: { if !$0 { pendingPeriod = nil } }
            ),
            presenting: pendingPeriod
        ) { period in
            Button("Turn On Auto-Delete", role: .destructive) {
                autoDeleteDays = period.rawValue
                autoDeleteEnabled = true
            }
            Button("Cancel", role: .cancel) {}
        } message: { period in
            Text(confirmationMessage(for: period))
        }
    }

    private var currentPeriod: RetentionPeriod {
        RetentionPeriod(rawValue: autoDeleteDays) ?? PhotoRetention.defaultPeriod
    }

    private var autoDeleteBinding: Binding<Bool> {
        Binding(
            get: { autoDeleteEnabled },
            set: { isOn in
                if isOn {
                    pendingPeriod = currentPeriod
                } else {
                    autoDeleteEnabled = false
                }
            }
        )
    }

    private var periodBinding: Binding<RetentionPeriod> {
        Binding(
            get: { currentPeriod },
            set: { period in
                // A shorter period can delete photos as soon as you return to the library, so confirm it.
                if matchCount(for: period) > matchCount(for: currentPeriod) {
                    pendingPeriod = period
                } else {
                    autoDeleteDays = period.rawValue
                }
            }
        )
    }

    private func matchCount(for period: RetentionPeriod) -> Int {
        PhotoRetention.olderThan(period, in: photos).count
    }

    private var autoDeleteFooter: String {
        guard autoDeleteEnabled else {
            return "Off. Nothing is deleted unless you delete it."
        }
        return "Photos older than \(currentPeriod.label) are permanently deleted when you open the app. Photos marked Keep are never auto-deleted."
    }

    private func confirmationMessage(for period: RetentionPeriod) -> String {
        let count = matchCount(for: period)
        let photosText = count == 1 ? "1 photo is" : "\(count) photos are"
        return "\(photosText) already older than \(period.label) and will be permanently deleted as soon as you return to the library. Photos marked Keep are safe."
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(for: PhotoRecord.self, inMemory: true)
}
