//
//  HobbsCameraTests.swift
//  HobbsCameraTests
//
//  Created by Stella Lu on 1/18/26.
//

import CoreLocation
import Foundation
import ImageIO
import SwiftData
import Testing
import UIKit
@testable import HobbsCamera

// MARK: - Helpers

private let captureDate = Date(timeIntervalSince1970: 1_790_000_000)

private func makeLocation(
    latitude: Double = 47.5,
    longitude: Double = -122.3,
    altitude: Double = 100,
    accuracy: Double = 10,
    verticalAccuracy: Double = 15,
    secondsBeforeCapture: TimeInterval = 0
) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
        altitude: altitude,
        horizontalAccuracy: accuracy,
        verticalAccuracy: verticalAccuracy,
        timestamp: captureDate.addingTimeInterval(-secondsBeforeCapture)
    )
}

private func makeJPEG() -> Data {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
    let image = renderer.image { context in
        UIColor.blue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    return image.jpegData(compressionQuality: 0.9)!
}

private func imageProperties(at url: URL) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

private func makeRecord(ageDays: Double, now: Date, kept: Bool = false) -> PhotoRecord {
    let record = PhotoRecord(
        filePath: "\(UUID().uuidString).jpg",
        createdAt: now.addingTimeInterval(-ageDays * 24 * 60 * 60),
        thumbnailPath: "\(UUID().uuidString)_thumb.jpg"
    )
    record.isKept = kept
    return record
}

// MARK: - Choosing a location

struct LocationFixPolicyTests {
    @Test func usesLiveFixNearCapture() {
        let fix = LocationFixPolicy.resolve(
            recent: [makeLocation(secondsBeforeCapture: 2)],
            lastKnown: nil,
            captureDate: captureDate
        )
        #expect(fix.status == .live)
        #expect(fix.location?.latitude == 47.5)
    }

    @Test func prefersGoodFixClosestToShutter() {
        let fix = LocationFixPolicy.resolve(
            recent: [
                makeLocation(latitude: 1, accuracy: 5, secondsBeforeCapture: 20),
                makeLocation(latitude: 2, accuracy: 30, secondsBeforeCapture: 1)
            ],
            lastKnown: nil,
            captureDate: captureDate
        )
        #expect(fix.location?.latitude == 2)
    }

    @Test func usesMostAccurateFixWhenNoneAreGood() {
        let fix = LocationFixPolicy.resolve(
            recent: [
                makeLocation(latitude: 1, accuracy: 500),
                makeLocation(latitude: 2, accuracy: 200)
            ],
            lastKnown: nil,
            captureDate: captureDate
        )
        #expect(fix.status == .live)
        #expect(fix.location?.latitude == 2)
    }

    @Test func labelsOlderFixAsLastKnown() {
        let fix = LocationFixPolicy.resolve(
            recent: [],
            lastKnown: makeLocation(secondsBeforeCapture: 10 * 60),
            captureDate: captureDate
        )
        #expect(fix.status == .lastKnown)
        #expect(fix.location != nil)
    }

    @Test func rejectsFixOlderThanLimit() {
        let fix = LocationFixPolicy.resolve(
            recent: [],
            lastKnown: makeLocation(secondsBeforeCapture: 20 * 60),
            captureDate: captureDate
        )
        #expect(fix.status == .unavailable)
        #expect(fix.location == nil)
    }

    @Test func ignoresInvalidFix() {
        let fix = LocationFixPolicy.resolve(
            recent: [makeLocation(accuracy: -1)],
            lastKnown: nil,
            captureDate: captureDate
        )
        #expect(fix.status == .unavailable)
    }

    @Test func goodFixMustBeAccurateAndCurrent() {
        #expect(LocationFixPolicy.isGood(makeLocation(accuracy: 20), forCaptureAt: captureDate))
        #expect(!LocationFixPolicy.isGood(makeLocation(accuracy: 500), forCaptureAt: captureDate))
        #expect(!LocationFixPolicy.isGood(makeLocation(accuracy: 20, secondsBeforeCapture: 120), forCaptureAt: captureDate))
    }
}

// MARK: - Metadata written into the file

struct PhotoMetadataStampingTests {
    private func savedProperties(location: CapturedLocation?) throws -> [CFString: Any] {
        let url = try AppPhotoStore.saveJPEGToPrivateLibrary(makeJPEG(), createdAt: captureDate, location: location)
        defer { try? FileManager.default.removeItem(at: url) }
        return try imageProperties(at: url)
    }

    @Test func writesLocationAndFixTime() throws {
        let location = CapturedLocation(makeLocation(latitude: 47.5, longitude: -122.3, altitude: 100, accuracy: 12))
        let gps = try #require(try savedProperties(location: location)[kCGImagePropertyGPSDictionary] as? [CFString: Any])

        #expect(abs((gps[kCGImagePropertyGPSLatitude] as? Double ?? 0) - 47.5) < 0.0001)
        #expect(gps[kCGImagePropertyGPSLatitudeRef] as? String == "N")
        #expect(abs((gps[kCGImagePropertyGPSLongitude] as? Double ?? 0) - 122.3) < 0.0001)
        #expect(gps[kCGImagePropertyGPSLongitudeRef] as? String == "W")
        #expect(abs((gps[kCGImagePropertyGPSAltitude] as? Double ?? 0) - 100) < 0.01)
        #expect(abs((gps[kCGImagePropertyGPSHPositioningError] as? Double ?? 0) - 12) < 0.01)

        // 1_790_000_000 is 2026-09-21 14:13:20 UTC.
        #expect(gps[kCGImagePropertyGPSDateStamp] as? String == "2026:09:21")
        #expect((gps[kCGImagePropertyGPSTimeStamp] as? String)?.hasPrefix("14:13:20") == true)
    }

    @Test func writesSouthernAndEasternHemispheres() throws {
        let location = CapturedLocation(makeLocation(latitude: -33.9, longitude: 151.2))
        let gps = try #require(try savedProperties(location: location)[kCGImagePropertyGPSDictionary] as? [CFString: Any])

        #expect(gps[kCGImagePropertyGPSLatitudeRef] as? String == "S")
        #expect(gps[kCGImagePropertyGPSLongitudeRef] as? String == "E")
        #expect((gps[kCGImagePropertyGPSLatitude] as? Double ?? 0) > 0)
    }

    @Test func omitsGPSWithoutLocationButKeepsTime() throws {
        let properties = try savedProperties(location: nil)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)

        let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])
        #expect(exif[kCGImagePropertyExifDateTimeOriginal] != nil)
    }

    @Test func pipelineSavesMatchingRecord() async throws {
        let location = CapturedLocation(makeLocation(latitude: 40, longitude: -105, altitude: 1600))
        let record = try await PhotoSavePipeline().run(
            capture: PhotoCapture(jpegData: makeJPEG(), createdAt: captureDate),
            locationFix: LocationFix(status: .live, location: location)
        )
        defer {
            try? AppPhotoStore.deletePhotoAndThumbnail(
                photoStoredValue: record.filePath,
                thumbnailStoredValue: record.thumbnailPath
            )
        }

        #expect(record.latitude == 40)
        #expect(record.longitude == -105)
        #expect(record.altitude == 1600)
        #expect(record.locationStatus == .live)
        #expect(record.locationTimestamp == captureDate)
        #expect(record.captureTimeZoneIdentifier == TimeZone.current.identifier)
        #expect(record.clLocation?.coordinate.latitude == 40)
        #expect(record.mapsURL != nil)

        let url = try #require(record.photoURL)
        #expect(try imageProperties(at: url)[kCGImagePropertyGPSDictionary] != nil)
        #expect(record.thumbnailURL != nil)
    }

    @Test func pipelineRecordsMissingLocation() async throws {
        let record = try await PhotoSavePipeline().run(
            capture: PhotoCapture(jpegData: makeJPEG(), createdAt: captureDate),
            locationFix: LocationFix(status: .denied, location: nil)
        )
        defer {
            try? AppPhotoStore.deletePhotoAndThumbnail(
                photoStoredValue: record.filePath,
                thumbnailStoredValue: record.thumbnailPath
            )
        }

        #expect(record.latitude == nil)
        #expect(record.locationStatus == .denied)
        #expect(record.clLocation == nil)
        #expect(record.mapsURL == nil)
    }
}

// MARK: - Formatting

struct PhotoMetadataFormatTests {
    @Test func formatsUTC() {
        #expect(PhotoMetadataFormat.utc(captureDate) == "2026-09-21 14:13:20 UTC")
    }

    @Test func describesFixOffset() {
        #expect(PhotoMetadataFormat.fixOffset(fix: captureDate, capture: captureDate) == "Same second as photo")
        #expect(PhotoMetadataFormat.fixOffset(fix: captureDate.addingTimeInterval(-5), capture: captureDate) == "5 s before photo")
        #expect(PhotoMetadataFormat.fixOffset(fix: captureDate.addingTimeInterval(3), capture: captureDate) == "3 s after photo")
        #expect(PhotoMetadataFormat.fixOffset(fix: captureDate.addingTimeInterval(-600), capture: captureDate) == "10 min before photo")
    }
}

// MARK: - Old photos

@MainActor
struct PhotoRetentionTests {
    private let now = captureDate

    private func makeDefaults(enabled: Bool, period: RetentionPeriod) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "HobbsCameraTests.\(UUID().uuidString)")!
        defaults.set(enabled, forKey: PhotoRetention.autoDeleteEnabledKey)
        defaults.set(period.rawValue, forKey: PhotoRetention.autoDeleteDaysKey)
        return defaults
    }

    private func makeContext(_ records: [PhotoRecord]) throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PhotoRecord.self, configurations: config)
        let context = ModelContext(container)
        records.forEach(context.insert)
        try context.save()
        return context
    }

    @Test func selectsOnlyOlderPhotos() {
        let old = makeRecord(ageDays: 40, now: now)
        let recent = makeRecord(ageDays: 20, now: now)

        let result = PhotoRetention.olderThan(.days30, in: [old, recent], now: now)
        #expect(result.map(\.id) == [old.id])
    }

    @Test func skipsKeptPhotos() {
        let kept = makeRecord(ageDays: 400, now: now, kept: true)
        #expect(PhotoRetention.olderThan(.days30, in: [kept], now: now).isEmpty)
    }

    @Test func keepFlagTogglesWithoutAffectingOtherFlags() {
        let record = makeRecord(ageDays: 1, now: now)
        record.flags = 0b100
        record.isKept = true
        #expect(record.isKept)
        #expect(record.flags == 0b101)
        record.isKept = false
        #expect(!record.isKept)
        #expect(record.flags == 0b100)
    }

    @Test func autoDeleteDoesNothingByDefault() throws {
        let context = try makeContext([makeRecord(ageDays: 4000, now: now)])
        let defaults = UserDefaults(suiteName: "HobbsCameraTests.\(UUID().uuidString)")!

        let deleted = PhotoRetention.runAutoDeleteIfEnabled(in: context, defaults: defaults, now: now)

        #expect(deleted.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<PhotoRecord>()) == 1)
    }

    @Test func autoDeleteDoesNothingWhenOff() throws {
        let context = try makeContext([makeRecord(ageDays: 4000, now: now)])
        let defaults = makeDefaults(enabled: false, period: .days30)

        #expect(PhotoRetention.runAutoDeleteIfEnabled(in: context, defaults: defaults, now: now).isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<PhotoRecord>()) == 1)
    }

    @Test func autoDeleteRemovesOnlyExpiredUnkeptPhotos() throws {
        let expired = makeRecord(ageDays: 40, now: now)
        let recent = makeRecord(ageDays: 10, now: now)
        let kept = makeRecord(ageDays: 40, now: now, kept: true)
        let expiredID = expired.id
        let context = try makeContext([expired, recent, kept])
        let defaults = makeDefaults(enabled: true, period: .days30)

        let deleted = PhotoRetention.runAutoDeleteIfEnabled(in: context, defaults: defaults, now: now)

        #expect(deleted == [expiredID])
        #expect(try context.fetchCount(FetchDescriptor<PhotoRecord>()) == 2)
    }

    @Test func deleteRemovesFilesFromDisk() async throws {
        let record = try await PhotoSavePipeline().run(
            capture: PhotoCapture(jpegData: makeJPEG(), createdAt: captureDate),
            locationFix: LocationFix(status: .unavailable, location: nil)
        )
        let context = try makeContext([record])
        let photoURL = try #require(record.photoURL)
        let thumbnailURL = try #require(record.thumbnailURL)

        try PhotoRetention.delete([record], in: context)

        #expect(!FileManager.default.fileExists(atPath: photoURL.path))
        #expect(!FileManager.default.fileExists(atPath: thumbnailURL.path))
        #expect(try context.fetchCount(FetchDescriptor<PhotoRecord>()) == 0)
    }
}

// MARK: - Upgrading existing photos

/// `PhotoRecord` exactly as it was before location was added.
private enum PreLocationSchema {
    @Model
    final class PhotoRecord {
        @Attribute(.unique) var id: UUID
        var filePath: String
        var createdAt: Date
        var thumbnailPath: String
        var flags: Int

        init(id: UUID, filePath: String, createdAt: Date, thumbnailPath: String, flags: Int) {
            self.id = id
            self.filePath = filePath
            self.createdAt = createdAt
            self.thumbnailPath = thumbnailPath
            self.flags = flags
        }
    }
}

struct PhotoRecordMigrationTests {
    @Test func existingPhotosSurviveUpgrade() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("migration.store")
        let id = UUID()

        do {
            let schema = Schema([PreLocationSchema.PhotoRecord.self])
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
            let context = ModelContext(container)
            context.insert(PreLocationSchema.PhotoRecord(
                id: id,
                filePath: "old.jpg",
                createdAt: captureDate,
                thumbnailPath: "old_thumb.jpg",
                flags: 0
            ))
            try context.save()
        }

        let schema = Schema([PhotoRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let records = try ModelContext(container).fetch(FetchDescriptor<PhotoRecord>())

        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(record.id == id)
        #expect(record.filePath == "old.jpg")
        #expect(record.createdAt == captureDate)
        #expect(record.latitude == nil)
        #expect(record.locationStatus == nil)
        #expect(!record.isKept)
    }
}
