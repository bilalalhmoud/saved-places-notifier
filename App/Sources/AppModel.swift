import Foundation
import SwiftUI
import SwiftData
import CoreLocation
import Combine
import SavedPlacesCore

/// The app's coordinator. Owns the spatial index, ties Core Location updates to
/// the proximity engine, fires notifications, and exposes state to the UI.
@MainActor
final class AppModel: ObservableObject {
    let settings = AppSettings()
    let locationManager = LocationManager()
    let notificationManager = NotificationManager()
    private let engine = ProximityEngine()
    private let index = SpatialIndex()

    private var modelContext: ModelContext?
    private var placesByID: [UUID: SavedPlace] = [:]

    @Published private(set) var proximityState = AppModel.loadState()
    @Published private(set) var nearby: [NearbyResult] = []
    @Published private(set) var placeCount = 0
    @Published private(set) var categories: [String] = []
    @Published var notificationsAuthorized = false
    /// Set when a notification is tapped so the UI can present that place.
    @Published var selectedPlaceID: UUID?

    private static let stateKey = "proximity.state.v1"

    // MARK: Lifecycle

    func configure(with context: ModelContext) {
        self.modelContext = context
        reload()
        locationManager.onLocationUpdate = { [weak self] location in
            self?.handle(location: location)
        }
    }

    func start() {
        locationManager.requestAuthorization()
        locationManager.startMonitoring()
        Task { notificationsAuthorized = await notificationManager.requestAuthorization() }
    }

    /// Reloads places from the store and rebuilds the spatial index.
    func reload() {
        guard let context = modelContext else { return }
        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        placesByID = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0) })
        index.build(from: places.map { $0.indexed })
        placeCount = places.count
        categories = Set(places.compactMap { $0.category }).sorted()
        refreshNearby()
    }

    // MARK: Location handling

    private func handle(location: CLLocation) {
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let mode = effectiveMode(for: location)

        refreshNearby(at: coordinate, mode: mode)

        // Respect allowed transport modes and time windows before notifying.
        guard settings.allowedTransportModes.contains(mode) || settings.manualTransportMode != nil else { return }
        guard settings.timeWindow.allows(Date()) else { return }

        let config = settings.proximityConfig(enabledCategories: enabledCategories())
        let outcome = engine.evaluate(
            current: coordinate,
            mode: settings.adaptiveRadius ? mode : .any,
            index: index,
            categoryProvider: { [weak self] id in self?.placesByID[id]?.category },
            config: config,
            state: proximityState,
            now: Date()
        )
        proximityState = outcome.state
        Self.saveState(outcome.state)

        if !outcome.events.isEmpty {
            notificationManager.present(events: outcome.events, places: placesByID)
            let now = Date()
            for event in outcome.events { placesByID[event.id]?.lastNotification = now }
            try? modelContext?.save()
        }

        adjustAccuracy(basedOn: outcome.effectiveRadiusMeters, at: coordinate)
    }

    /// Raises accuracy when a saved place is within twice the notification radius,
    /// otherwise drops back to low power — the core of the battery strategy.
    private func adjustAccuracy(basedOn radius: Double, at coordinate: Coordinate) {
        guard settings.batteryMode != .saver else { return }
        let approaching = !index.nearby(to: coordinate, radiusMeters: radius * 2).isEmpty
        if approaching || settings.batteryMode == .precise {
            locationManager.startPreciseUpdates()
        } else {
            locationManager.stopPreciseUpdates()
        }
    }

    private func effectiveMode(for location: CLLocation) -> TransportMode {
        if let manual = settings.manualTransportMode { return manual }
        return LocationManager.mode(forSpeed: location.speed)
    }

    private func enabledCategories() -> Set<String>? {
        let enabled = Set(categories).subtracting(settings.disabledCategories)
        // nil means "all enabled" — only constrain when the user disabled some.
        return settings.disabledCategories.isEmpty ? nil : enabled
    }

    // MARK: Nearby (UI)

    func refreshNearby() {
        guard let location = locationManager.lastLocation else { return }
        let coordinate = Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        refreshNearby(at: coordinate, mode: locationManager.detectedMode)
    }

    private func refreshNearby(at coordinate: Coordinate, mode: TransportMode) {
        let radius = max(settings.baseRadiusMeters, mode.radius(base: settings.baseRadiusMeters))
        nearby = index.nearby(to: coordinate, radiusMeters: radius)
    }

    func place(for id: UUID) -> SavedPlace? { placesByID[id] }

    // MARK: Import / mutations

    @discardableResult
    func importPlaces(from url: URL) throws -> Int {
        guard let context = modelContext else { return 0 }
        let records = try ImportService.importFile(at: url)
        var inserted = 0
        for record in records {
            // De-duplicate by Google place ID, else by rounded coordinates + title.
            if isDuplicate(record) { continue }
            context.insert(SavedPlace(record: record))
            inserted += 1
        }
        try context.save()
        reload()
        return inserted
    }

    private func isDuplicate(_ record: PlaceRecord) -> Bool {
        if let gid = record.googlePlaceID, !gid.isEmpty {
            return placesByID.values.contains { $0.googlePlaceID == gid }
        }
        return placesByID.values.contains {
            $0.title == record.title &&
            abs($0.latitude - record.coordinate.latitude) < 0.00005 &&
            abs($0.longitude - record.coordinate.longitude) < 0.00005
        }
    }

    func markVisited(_ place: SavedPlace) {
        place.lastVisited = Date()
        try? modelContext?.save()
    }

    func toggleFavourite(_ place: SavedPlace) {
        place.favourite.toggle()
        try? modelContext?.save()
    }

    func delete(_ place: SavedPlace) {
        modelContext?.delete(place)
        try? modelContext?.save()
        reload()
    }

    func deleteAll() {
        guard let context = modelContext else { return }
        for place in placesByID.values { context.delete(place) }
        try? context.save()
        proximityState = ProximityState()
        Self.saveState(proximityState)
        reload()
    }

    // MARK: Dedup-state persistence

    private static func loadState() -> ProximityState {
        guard let data = UserDefaults.standard.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(ProximityState.self, from: data) else {
            return ProximityState()
        }
        return state
    }

    private static func saveState(_ state: ProximityState) {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }
}
