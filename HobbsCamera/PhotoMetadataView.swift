// PhotoMetadataView.swift
import MapKit
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

    /// Large time for the detail header, e.g. "14:32:05".
    static func clock(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    static func longDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE, MMM d, yyyy · zzz"
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

/// The full time and location record for a photo, as cards.
struct PhotoMetadataView: View {
    let record: PhotoRecord

    /// Above this, the location is flagged as imprecise.
    private let lowAccuracyMeters = 100.0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            timeCard
            locationCard
        }
        .textSelection(.enabled)
    }

    // MARK: - Header

    private var header: some View {
        let style = record.locationStatus.style
        return VStack(alignment: .leading, spacing: 8) {
            Text(PhotoMetadataFormat.clock(record.createdAt, timeZone: record.captureTimeZone))
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
            Text(PhotoMetadataFormat.longDate(record.createdAt, timeZone: record.captureTimeZone))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            StatusChip(icon: style.icon, text: style.label, color: style.color)
                .padding(.top, 4)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Time

    private var timeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Time")

            row("UTC", PhotoMetadataFormat.utc(record.createdAt))
            divider
            row("Local", PhotoMetadataFormat.local(record.createdAt, timeZone: record.captureTimeZone))

            if let fixTime = record.locationTimestamp {
                divider
                row("Location fix", PhotoMetadataFormat.utc(fixTime))
                divider
                row("Fix taken", PhotoMetadataFormat.fixOffset(fix: fixTime, capture: record.createdAt))

                Text("Times come from the phone’s clock. iOS doesn’t provide raw GPS time, so the fix time may follow the same clock.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .card()
    }

    // MARK: - Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Location")

            if let note = statusNote {
                Label(note, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.caution)
            }

            if let latitude = record.latitude, let longitude = record.longitude {
                map(latitude: latitude, longitude: longitude)

                row("Coordinates", PhotoMetadataFormat.coordinates(latitude: latitude, longitude: longitude))

                if let accuracy = record.horizontalAccuracy {
                    divider
                    row("Accuracy", PhotoMetadataFormat.accuracy(meters: accuracy))
                    if accuracy > lowAccuracyMeters {
                        Label("Low accuracy. The true position could be well away from these coordinates.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.caution)
                    }
                }

                if let altitude = record.altitude {
                    divider
                    row("Altitude (GPS)", PhotoMetadataFormat.altitude(meters: altitude))
                }
                if let verticalAccuracy = record.verticalAccuracy {
                    divider
                    row("Altitude accuracy", PhotoMetadataFormat.accuracy(meters: verticalAccuracy))
                }

                if let url = record.mapsURL {
                    Link(destination: url) {
                        Label("Open in Maps", systemImage: "arrow.up.right")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(.top, 2)
                }
            }
        }
        .card()
    }

    private func map(latitude: Double, longitude: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let radius = max(record.horizontalAccuracy ?? 0, 0)
        let span = max(radius * 6, 400)

        return Map(
            initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span)),
            interactionModes: []
        ) {
            if radius > 0 {
                MapCircle(center: coordinate, radius: radius)
                    .foregroundStyle(Color.accentColor.opacity(0.18))
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
            }
            Annotation("", coordinate: coordinate) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                    .shadow(radius: 3)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private var statusNote: String? {
        switch record.locationStatus {
        case .live:
            return nil
        case .lastKnown:
            return "No current fix was available, so this shows where the phone was earlier."
        case .unavailable:
            return "No GPS fix was available when this photo was taken."
        case .denied:
            return "HobbsCamera wasn’t allowed to use location when this photo was taken."
        case nil:
            return "This photo was taken before HobbsCamera recorded location."
        }
    }

    // MARK: - Rows

    private var divider: some View {
        Divider().overlay(Theme.cardStroke)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .multilineTextAlignment(.trailing)
        }
    }
}
