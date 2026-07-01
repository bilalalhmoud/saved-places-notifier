import Foundation
import SwiftUI
import SavedPlacesCore

/// Battery strategy, mapped to how aggressively we track location.
enum BatteryMode: String, CaseIterable, Identifiable, Codable {
    case saver      // significant-change + visits only
    case balanced   // adds finer tracking when a place is near
    case precise    // standard updates while foregrounded

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .saver: return "Battery Saver"
        case .balanced: return "Balanced"
        case .precise: return "High Accuracy"
        }
    }
}

/// When notifications are allowed to fire, by time of day / week.
enum TimeWindow: String, CaseIterable, Identifiable, Codable {
    case anytime
    case daytime      // 08:00–21:00
    case businessHours // 09:00–17:00
    case weekdays
    case weekends

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .anytime: return "Any time"
        case .daytime: return "Daytime (8am–9pm)"
        case .businessHours: return "Business hours (9am–5pm)"
        case .weekdays: return "Weekdays only"
        case .weekends: return "Weekends only"
        }
    }

    func allows(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        let isWeekend = (weekday == 1 || weekday == 7)
        switch self {
        case .anytime: return true
        case .daytime: return hour >= 8 && hour < 21
        case .businessHours: return hour >= 9 && hour < 17
        case .weekdays: return !isWeekend
        case .weekends: return isWeekend
        }
    }
}

/// User-facing app settings, persisted to `UserDefaults` as JSON.
@MainActor
final class AppSettings: ObservableObject {
    @Published var baseRadiusMeters: Double { didSet { save() } }
    @Published var cooldown: Cooldown { didSet { save() } }
    @Published var maxNotificationsPerBatch: Int { didSet { save() } }
    @Published var minMinutesBetweenNotifications: Int { didSet { save() } }
    @Published var batteryMode: BatteryMode { didSet { save() } }
    @Published var adaptiveRadius: Bool { didSet { save() } }
    /// Manual transport override; `nil` means auto-detect from speed.
    @Published var manualTransportMode: TransportMode? { didSet { save() } }
    @Published var allowedTransportModes: Set<TransportMode> { didSet { save() } }
    @Published var timeWindow: TimeWindow { didSet { save() } }
    @Published var disabledCategories: Set<String> { didSet { save() } }
    @Published var preferGoogleMaps: Bool { didSet { save() } }

    private static let key = "app.settings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            baseRadiusMeters = stored.baseRadiusMeters
            cooldown = stored.cooldown
            maxNotificationsPerBatch = stored.maxNotificationsPerBatch
            minMinutesBetweenNotifications = stored.minMinutesBetweenNotifications
            batteryMode = stored.batteryMode
            adaptiveRadius = stored.adaptiveRadius
            manualTransportMode = stored.manualTransportMode
            allowedTransportModes = stored.allowedTransportModes
            timeWindow = stored.timeWindow
            disabledCategories = stored.disabledCategories
            preferGoogleMaps = stored.preferGoogleMaps
        } else {
            baseRadiusMeters = 500
            cooldown = .untilLeave
            maxNotificationsPerBatch = 5
            minMinutesBetweenNotifications = 5
            batteryMode = .balanced
            adaptiveRadius = true
            manualTransportMode = nil
            allowedTransportModes = Set(TransportMode.allCases)
            timeWindow = .anytime
            disabledCategories = []
            preferGoogleMaps = true
        }
    }

    /// Builds the core engine configuration from current settings.
    func proximityConfig(enabledCategories: Set<String>?) -> ProximityConfig {
        ProximityConfig(
            baseRadiusMeters: baseRadiusMeters,
            cooldown: cooldown,
            enabledCategories: enabledCategories,
            maxNotificationsPerBatch: maxNotificationsPerBatch,
            minSecondsBetweenNotifications: TimeInterval(minMinutesBetweenNotifications * 60)
        )
    }

    private struct Stored: Codable {
        var baseRadiusMeters: Double
        var cooldown: Cooldown
        var maxNotificationsPerBatch: Int
        var minMinutesBetweenNotifications: Int
        var batteryMode: BatteryMode
        var adaptiveRadius: Bool
        var manualTransportMode: TransportMode?
        var allowedTransportModes: Set<TransportMode>
        var timeWindow: TimeWindow
        var disabledCategories: Set<String>
        var preferGoogleMaps: Bool
    }

    private func save() {
        let stored = Stored(
            baseRadiusMeters: baseRadiusMeters,
            cooldown: cooldown,
            maxNotificationsPerBatch: maxNotificationsPerBatch,
            minMinutesBetweenNotifications: minMinutesBetweenNotifications,
            batteryMode: batteryMode,
            adaptiveRadius: adaptiveRadius,
            manualTransportMode: manualTransportMode,
            allowedTransportModes: allowedTransportModes,
            timeWindow: timeWindow,
            disabledCategories: disabledCategories,
            preferGoogleMaps: preferGoogleMaps
        )
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
