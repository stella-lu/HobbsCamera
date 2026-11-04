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
}

/// The time and location of a photo, as cards.
struct PhotoMetadataView: View {
    let record: PhotoRecord

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
        VStack(alignment: .leading, spacing: 8) {
            Text(PhotoMetadataFormat.clock(record.createdAt, timeZone: record.captureTimeZone))
                .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
            Text(PhotoMetadataFormat.longDate(record.createdAt, timeZone: record.captureTimeZone))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
        }
        .card()
    }

    // MARK: - Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Location")

            if let latitude = record.latitude, let longitude = record.longitude {
                map(latitude: latitude, longitude: longitude)

                row("Coordinates", PhotoMetadataFormat.coordinates(latitude: latitude, longitude: longitude))

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
            } else {
                Text("No location recorded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func map(latitude: Double, longitude: Double) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        return Map(
            initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 600, longitudinalMeters: 600)),
            interactionModes: []
        ) {
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
