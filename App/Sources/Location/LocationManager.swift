import Foundation
import CoreLocation
import Combine
import SavedPlacesCore

/// Wraps Core Location with a battery-conscious strategy:
/// significant-location-change + visit monitoring as the always-on baseline,
/// optionally upgrading to standard updates when the user is near a saved place.
@MainActor
final class LocationManager: NSObject, ObservableObject {
    private let manager = CLLocationManager()

    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastLocation: CLLocation?
    @Published var detectedMode: TransportMode = .any

    /// Called on every meaningful location update (significant change, visit, or
    /// standard update). The coordinator hooks the proximity engine here.
    var onLocationUpdate: ((CLLocation) -> Void)?

    private var preciseUpdatesActive = false

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .otherNavigation
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// Starts the low-power baseline monitoring.
    func startMonitoring() {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        if authorizationStatus == .authorizedAlways {
            manager.allowsBackgroundLocationUpdates = true
        }
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
        manager.requestLocation()
    }

    func stopMonitoring() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        stopPreciseUpdates()
    }

    /// Temporarily raises accuracy (used when a saved place is nearby).
    func startPreciseUpdates() {
        guard !preciseUpdatesActive else { return }
        preciseUpdatesActive = true
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.startUpdatingLocation()
    }

    func stopPreciseUpdates() {
        guard preciseUpdatesActive else { return }
        preciseUpdatesActive = false
        manager.stopUpdatingLocation()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Derives transport mode from instantaneous speed (m/s).
    static func mode(forSpeed speed: CLLocationSpeed) -> TransportMode {
        guard speed >= 0 else { return .any }
        switch speed {
        case ..<1.8: return .walking   // < ~6.5 km/h
        case ..<7.0: return .cycling   // < ~25 km/h
        default:     return .driving
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedAlways {
                self.startMonitoring()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = location
            self.detectedMode = LocationManager.mode(forSpeed: location.speed)
            self.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // A visit gives us a fresh, low-power fix — treat it like a location update.
        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        Task { @MainActor in
            self.lastLocation = location
            self.onLocationUpdate?(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures are expected (e.g. no fix yet); ignore.
    }
}
