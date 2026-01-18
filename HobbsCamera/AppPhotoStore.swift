import Foundation

enum AppPhotoStore {
    static func photosDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let appDir = base.appendingPathComponent("HobbsCamera", isDirectory: true)
        let photosDir = appDir.appendingPathComponent("photos", isDirectory: true)

        try FileManager.default.createDirectory(at: photosDir, withIntermediateDirectories: true)

        // Exclude the whole appDir from iCloud backup
        try excludeFromBackup(url: appDir)

        return photosDir
    }

    static func saveJPEGToPrivateLibrary(data: Data) throws -> URL {
        let dir = try photosDirectoryURL()
        let filename = UUID().uuidString + ".jpg"
        let url = dir.appendingPathComponent(filename)

        // Atomic write for safety
        try data.write(to: url, options: [.atomic])

        // Exclude individual file too (belt and suspenders)
        try excludeFromBackup(url: url)

        return url
    }

    private static func excludeFromBackup(url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
