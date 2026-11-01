// LocationService.swift
import CoreLocation
import Foundation

/// A Sendable snapshot of the location attached to a photo.
struct CapturedLocation: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    /// Radius of uncertainty in meters.
    let horizontalAccuracy: Double
    /// Meters above mean sea level. Nil when iOS did not provide a valid altitude.
    let altitude: Double?
    let verticalAccuracy: Double?
    /// When the fix was determined.
    let timestamp: Date

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        horizontalAccuracy = location.horizontalAccuracy
        let hasAltitude = location.verticalAccuracy > 0
        altitude = hasAltitude ? location.altitude : nil
        verticalAccuracy = hasAltitude ? location.verticalAccuracy : nil
        timestamp = location.timestamp
    }
}

/// How the location on a photo was obtained. Stored on `PhotoRecord` as its raw value.
enum LocationStatus: String, Sendable {
    /// A fix from around the moment of capture.
    case live
    /// An older fix, used because no current fix arrived in time.
    case lastKnown
    /// Location was allowed, but no usable fix was available.
    case unavailable
    /// The app was not allowed to use location.
    case denied
}

/// The location decision for one photo.
struct LocationFix: Sendable, Equatable {
    let status: LocationStatus
    let location: CapturedLocation?
}

/// The rules for choosing a photo's location. Kept free of `CLLocationManager` so they can be tested.
enum LocationFixPolicy {
    /// How long the camera waits after the shutter for a good fix.
    static let waitTimeoutSeconds: TimeInterval = 5

    /// A fix at least this accurate ends the wait.
    static let goodAccuracyMeters: CLLocationAccuracy = 65

    /// A fix within this many seconds of capture counts as live.
    static let liveWindowSeconds: TimeInterval = 30

    /// Older fixes are misleading (the aircraft may be at another airport), so they are not used at all.
    static let maxLastKnownAgeSeconds: TimeInterval = 15 * 60

    static func isValid(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0
    }

    static func isGood(_ location: CLLocation, forCaptureAt captureDate: Date) -> Bool {
        isValid(location)
            && location.horizontalAccuracy <= goodAccuracyMeters
            && abs(location.timestamp.timeIntervalSince(captureDate)) <= liveWindowSeconds
    }

    static func resolve(recent: [CLLocation], lastKnown: CLLocation?, captureDate: Date) -> LocationFix {
        let candidates = (recent + [lastKnown].compactMap { $0 }).filter(isValid)

        let live = candidates.filter {
            abs($0.timestamp.timeIntervalSince(captureDate)) <= liveWindowSeconds
        }
        let good = live.filter { $0.horizontalAccuracy <= goodAccuracyMeters }

        // Prefer the good fix closest to the shutter, otherwise whichever live fix is most accurate.
        let closest = good.min {
            abs($0.timestamp.timeIntervalSince(captureDate)) < abs($1.timestamp.timeIntervalSince(captureDate))
        }
        if let best = closest ?? live.min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) {
            return LocationFix(status: .live, location: CapturedLocation(best))
        }

        let older = candidates
            .filter {
                let age = captureDate.timeIntervalSince($0.timestamp)
                return age > 0 && age <= maxLastKnownAgeSeconds
            }
            .max { $0.timestamp < $1.timestamp }
        if let older {
            return LocationFix(status: .lastKnown, location: CapturedLocation(older))
        }

        return LocationFix(status: .unavailable, location: nil)
    }
}

/// Keeps GPS running while the camera is open, so a fix is usually ready before the shutter is pressed.
@MainActor
final class LocationService: NSObject, ObservableObject {
    enum Signal: Equatable {
        case searching
        case fix(accuracyMeters: Double)
        case denied
        case approximateOnly
    }

    @Published private(set) var signal: Signal = .searching

    private let manager = CLLocationManager()
    private var isRunning = false
    private var recentLocations: [CLLocation] = []

    private var waiter: CheckedContinuation<Void, Never>?
    private var waitingForCaptureAt: Date?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        isRunning = true
        updateSignalForAuthorization()

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stop() {
        isRunning = false
        manager.stopUpdatingLocation()
        wake()
    }

    /// Returns the location for a photo taken at `captureDate`, waiting briefly if there is no good fix yet.
    /// Never fails: a photo is always saved, with the status recording what happened.
    func fix(forCaptureAt captureDate: Date) async -> LocationFix {
        if isDenied {
            return LocationFix(status: .denied, location: nil)
        }

        let hasGoodFix = recentLocations.contains { LocationFixPolicy.isGood($0, forCaptureAt: captureDate) }
        if !hasGoodFix && isRunning {
            await waitForGoodFix(captureDate: captureDate)
        }

        if isDenied {
            return LocationFix(status: .denied, location: nil)
        }

        return LocationFixPolicy.resolve(
            recent: recentLocations,
            lastKnown: manager.location,
            captureDate: captureDate
        )
    }

    // MARK: - Waiting

    private func waitForGoodFix(captureDate: Date) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiter = continuation
            waitingForCaptureAt = captureDate
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(LocationFixPolicy.waitTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.wake()
            }
        }
    }

    private func wake() {
        timeoutTask?.cancel()
        timeoutTask = nil
        waitingForCaptureAt = nil
        waiter?.resume()
        waiter = nil
    }

    // MARK: - State

    private var isDenied: Bool {
        // This is also the status when Location Services is turned off for the whole device.
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    private func updateSignalForAuthorization() {
        if isDenied {
            signal = .denied
        } else if manager.accuracyAuthorization == .reducedAccuracy {
            signal = .approximateOnly
        } else if case .denied = signal {
            signal = .searching
        } else if case .approximateOnly = signal {
            signal = .searching
        }
    }

    private func handle(_ locations: [CLLocation]) {
        let now = Date()
        recentLocations.append(contentsOf: locations)
        recentLocations.removeAll { now.timeIntervalSince($0.timestamp) > LocationFixPolicy.liveWindowSeconds * 2 }

        if manager.accuracyAuthorization == .fullAccuracy,
           let latest = locations.last,
           LocationFixPolicy.isValid(latest) {
            signal = .fix(accuracyMeters: latest.horizontalAccuracy)
        }

        if let captureDate = waitingForCaptureAt,
           locations.contains(where: { LocationFixPolicy.isGood($0, forCaptureAt: captureDate) }) {
            wake()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    // CLLocationManager calls back on the thread it was created on, which is the main thread here.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated { handle(locations) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            updateSignalForAuthorization()
            if isDenied { wake() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Failures such as "no fix yet" are temporary. The capture timeout handles a fix that never comes.
    }
}
