// ShareSheet.swift
import SwiftUI
import UIKit

/// Identifies one set of files to share.
struct ShareRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Shares the original photo files, with their metadata, through the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing changes after the sheet is presented.
    }
}
