// LocationService.swift
import CoreLocation
import Foundation

/// A Sendable snapshot of the location attached to a photo.
struct CapturedLocation: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    /// Radius of uncertainty in meters. Written into the file's EXIF only.
    let horizontalAccuracy: Double
    /// Meters above mean sea level. Nil when iOS did not provide a valid altitude.
    let altitude: Double?
    /// When the fix was determined.
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        altitude = location.verticalAccuracy > 0 ? location.altitude : nil
        timestamp = location.timestamp
    }

    /// The fix to use for a photo taken at `captureDate`, or nil if there isn't a recent one.
    /// A stale fix is worse than none, since the aircraft may have flown somewhere else since.
    static func forCapture(at captureDate: Date, from location: CLLocation?) -> CapturedLocation? {
        guard let location,
              location.horizontalAccuracy >= 0,
              abs(captureDate.timeIntervalSince(location.timestamp)) <= maxAgeSeconds else {
            return nil
        }
        return CapturedLocation(location)
    }

    static let maxAgeSeconds: TimeInterval = 2 * 60
}

/// Keeps GPS running while the camera is open, so a location is usually ready when the shutter is pressed.
/// If there isn't one, the photo is saved with its time only.
@MainActor
final class LocationService: NSObject {
    private let manager = CLLocationManager()
    private var latest: CLLocation?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func location(forCaptureAt captureDate: Date) -> CapturedLocation? {
        CapturedLocation.forCapture(at: captureDate, from: latest ?? manager.location)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    // CLLocationManager calls back on the thread it was created on, which is the main thread here.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { latest = locations.last }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Failures such as "no fix yet" are temporary. A photo taken meanwhile just has no location.
    }
}
