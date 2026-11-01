// ShareSheet.swift
import SwiftUI
import UIKit

/// Identifies one set of files to share.
struct ShareRequest: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Shares the original photo files, with their metadata, through the system share sheet.
///
/// "Save Image" is removed because it would put the photo in Apple Photos, where Google Photos
/// could upload it. Saving to Apple Photos stays a separate action that warns about this first.
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.excludedActivityTypes = [.saveToCameraRoll]
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // Nothing changes after the sheet is presented.
    }
}
