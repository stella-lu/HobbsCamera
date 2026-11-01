// PhotoRetention.swift
import Foundation
import SwiftData

/// The age choices for "select older than" and auto-delete.
enum RetentionPeriod: Int, CaseIterable, Identifiable {
    case days30 = 30
    case days90 = 90
    case months6 = 180
    case year1 = 365
    case years2 = 730

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .days30: return "30 days"
        case .days90: return "90 days"
        case .months6: return "6 months"
        case .year1: return "1 year"
        case .years2: return "2 years"
        }
    }

    func cutoff(from now: Date) -> Date {
        now.addingTimeInterval(-TimeInterval(rawValue) * 24 * 60 * 60)
    }
}

/// Bulk selection and deletion of old photos.
///
/// Nothing is deleted automatically unless the user turns on auto-delete in Settings.
/// Photos marked Keep are never selected or deleted by age.
enum PhotoRetention {
    static let autoDeleteEnabledKey = "autoDeleteEnabled"
    static let autoDeleteDaysKey = "autoDeleteDays"
    static let defaultPeriod: RetentionPeriod = .year1

    static func olderThan(_ period: RetentionPeriod, in records: [PhotoRecord], now: Date = Date()) -> [PhotoRecord] {
        let cutoff = period.cutoff(from: now)
        return records.filter { !$0.isKept && $0.createdAt < cutoff }
    }

    /// Deletes the files and records for `records`, then saves.
    @MainActor
    static func delete(_ records: [PhotoRecord], in context: ModelContext) throws {
        for record in records {
            try AppPhotoStore.deletePhotoAndThumbnail(
                photoStoredValue: record.filePath,
                thumbnailStoredValue: record.thumbnailPath
            )
            context.delete(record)
        }
        try context.save()
    }

    /// Runs auto-delete if the user has turned it on, returning the IDs of the deleted photos.
    /// A photo that can't be deleted is skipped and tried again next time.
    @MainActor
    static func runAutoDeleteIfEnabled(
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        now: Date = Date()
    ) -> [UUID] {
        guard defaults.bool(forKey: autoDeleteEnabledKey),
              let period = RetentionPeriod(rawValue: defaults.integer(forKey: autoDeleteDaysKey)),
              let records = try? context.fetch(FetchDescriptor<PhotoRecord>()) else {
            return []
        }

        var deletedIDs: [UUID] = []
        for record in olderThan(period, in: records, now: now) {
            let id = record.id
            do {
                try delete([record], in: context)
                deletedIDs.append(id)
            } catch {
                continue
            }
        }
        return deletedIDs
    }
}
