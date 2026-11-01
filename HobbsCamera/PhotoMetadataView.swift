// PhotoMetadataView.swift
import SwiftUI

/// Formatting for the values shown on the photo detail screen.
enum PhotoMetadataFormat {
    static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }

    static func local(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d, yyyy, HH:mm:ss zzz"
        return formatter.string(from: date)
    }

    static func coordinates(latitude: Double, longitude: Double) -> String {
        String(format: "%.6f, %.6f", latitude, longitude)
    }

    static func accuracy(meters: Double) -> String {
        "±\(Int((meters * 3.28084).rounded())) ft (\(Int(meters.rounded())) m)"
    }

    static func altitude(meters: Double) -> String {
        "\(Int((meters * 3.28084).rounded())) ft (\(Int(meters.rounded())) m)"
    }

    /// Describes when the fix was taken relative to the photo.
    static func fixOffset(fix: Date, capture: Date) -> String {
        let seconds = Int(capture.timeIntervalSince(fix).rounded())
        let amount = abs(seconds)
        let duration = amount < 120 ? "\(amount) s" : "\(amount / 60) min"
        if seconds == 0 { return "Same second as photo" }
        return seconds > 0 ? "\(duration) before photo" : "\(duration) after photo"
    }
}

/// The full time and location record for a photo.
struct PhotoMetadataView: View {
    let record: PhotoRecord

    /// Above this, the location is flagged as imprecise.
    private let lowAccuracyMeters = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            timeSection
            locationSection
        }
        .textSelection(.enabled)
    }

    // MARK: - Time

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Time")
                .font(.headline)

            row("Phone clock (UTC)", PhotoMetadataFormat.utc(record.createdAt))
            row("Phone clock (local)", PhotoMetadataFormat.local(record.createdAt, timeZone: record.captureTimeZone))

            if let fixTime = record.locationTimestamp {
                row("Location fix time (UTC)", PhotoMetadataFormat.utc(fixTime))
                row("Fix taken", PhotoMetadataFormat.fixOffset(fix: fixTime, capture: record.createdAt))

                Text("iOS doesn’t provide raw GPS time. The fix time is its best estimate and may follow the phone’s clock, so a match doesn’t prove the clock was right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.headline)

            statusLabel

            if let latitude = record.latitude, let longitude = record.longitude {
                row("Coordinates", PhotoMetadataFormat.coordinates(latitude: latitude, longitude: longitude))

                if let accuracy = record.horizontalAccuracy {
                    row("Accuracy", PhotoMetadataFormat.accuracy(meters: accuracy))
                    if accuracy > lowAccuracyMeters {
                        warning("Low accuracy: the true position could be well away from these coordinates.")
                    }
                }

                if let altitude = record.altitude {
                    row("Altitude (GPS)", PhotoMetadataFormat.altitude(meters: altitude))
                }
                if let verticalAccuracy = record.verticalAccuracy {
                    row("Altitude accuracy", PhotoMetadataFormat.accuracy(meters: verticalAccuracy))
                }

                if let url = record.mapsURL {
                    Link(destination: url) {
                        Label("Open in Maps", systemImage: "map")
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch record.locationStatus {
        case .live:
            Label("Recorded at time of photo", systemImage: "location.fill")
                .font(.subheadline)
                .foregroundStyle(.green)
        case .lastKnown:
            warning("Last known location. No current fix was available, so this shows where the phone was earlier.")
        case .unavailable:
            warning("No location. No GPS fix was available when this photo was taken.")
        case .denied:
            warning("No location. HobbsCamera wasn’t allowed to use location when this photo was taken.")
        case nil:
            warning("No location. This photo was taken before HobbsCamera recorded location.")
        }
    }

    // MARK: - Rows

    private func row(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
        }
    }

    private func warning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
    }
}
