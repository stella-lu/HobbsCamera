// SettingsView.swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink {
                StorageView()
            } label: {
                Label("Storage", systemImage: "internaldrive")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
