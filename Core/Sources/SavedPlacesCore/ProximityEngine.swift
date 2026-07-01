import Foundation

/// User-tunable knobs for proximity notifications.
public struct ProximityConfig: Equatable, Sendable {
    /// Base notification radius (metres) before per-mode adaptation.
    public var baseRadiusMeters: Double
    public var cooldown: Cooldown
    /// Categories that may notify. `nil` means every category is enabled.
    public var enabledCategories: Set<String>?
    /// Maximum notifications emitted in a single evaluation (the rest stay pending).
    public var maxNotificationsPerBatch: Int
    /// Minimum seconds between any two notifications (global rate limit).
    public var minSecondsBetweenNotifications: TimeInterval

    public init(
        baseRadiusMeters: Double = 500,
        cooldown: Cooldown = .untilLeave,
        enabledCategories: Set<String>? = nil,
        maxNotificationsPerBatch: Int = 5,
        minSecondsBetweenNotifications: TimeInterval = 300
    ) {
        self.baseRadiusMeters = baseRadiusMeters
        self.cooldown = cooldown
        self.enabledCategories = enabledCategories
        self.maxNotificationsPerBatch = maxNotificationsPerBatch
        self.minSecondsBetweenNotifications = minSecondsBetweenNotifications
    }
}

/// Per-place membership state used to prevent duplicate notifications.
public struct PlaceProximityState: Equatable, Codable, Sendable {
    public var wasInside: Bool
    public var lastNotifiedAt: Date?

    public init(wasInside: Bool = false, lastNotifiedAt: Date? = nil) {
        self.wasInside = wasInside
        self.lastNotifiedAt = lastNotifiedAt
    }
}

/// The engine's memory between evaluations. Persist this so dedup survives relaunch.
public struct ProximityState: Equatable, Codable, Sendable {
    public var places: [UUID: PlaceProximityState]
    public var lastNotificationAt: Date?

    public init(places: [UUID: PlaceProximityState] = [:], lastNotificationAt: Date? = nil) {
        self.places = places
        self.lastNotificationAt = lastNotificationAt
    }
}

/// A single place that should be surfaced to the user right now.
public struct ProximityEvent: Equatable, Sendable {
    public let id: UUID
    public let distanceMeters: Double
}

public struct ProximityOutcome: Equatable, Sendable {
    public let events: [ProximityEvent]
    public let state: ProximityState
    /// The effective radius used, after mode adaptation (useful for UI/logging).
    public let effectiveRadiusMeters: Double
}

/// Turns a location update into a de-duplicated set of proximity notifications.
///
/// The engine is a pure function of its inputs: given the current location, the
/// spatial index and the previous `ProximityState`, it returns the events to
/// notify plus the new state. This makes the notification/dedup rules fully
/// unit-testable without Core Location or a device.
public struct ProximityEngine {
    public init() {}

    public func evaluate(
        current: Coordinate,
        mode: TransportMode,
        index: SpatialIndex,
        categoryProvider: (UUID) -> String?,
        config: ProximityConfig,
        state: ProximityState,
        now: Date
    ) -> ProximityOutcome {
        let radius = mode.radius(base: config.baseRadiusMeters)
        var newState = state

        // Places currently within the (adaptive) notification radius.
        let candidates = index.nearby(to: current, radiusMeters: radius)
        let insideNow = Set(candidates.map { $0.place.id })

        // Reset membership for places we previously flagged inside but have now left.
        for (id, placeState) in newState.places where placeState.wasInside && !insideNow.contains(id) {
            newState.places[id]?.wasInside = false
        }

        // Determine fresh entries eligible to notify (outside → inside transitions).
        var entries: [ProximityEvent] = []
        for candidate in candidates {
            let id = candidate.place.id
            let placeState = newState.places[id] ?? PlaceProximityState()

            // Already inside from a previous tick → no repeat until leave/return.
            if placeState.wasInside { continue }

            // Category filter.
            if let enabled = config.enabledCategories {
                let category = categoryProvider(id) ?? ""
                if !enabled.contains(category) { continue }
            }

            // Per-place cooldown time gate.
            if let last = placeState.lastNotifiedAt,
               now.timeIntervalSince(last) < config.cooldown.interval {
                continue
            }

            entries.append(ProximityEvent(id: id, distanceMeters: candidate.distanceMeters))
        }

        // Global rate limit: if we notified too recently, keep entries pending.
        if let lastGlobal = newState.lastNotificationAt,
           now.timeIntervalSince(lastGlobal) < config.minSecondsBetweenNotifications {
            return ProximityOutcome(events: [], state: newState, effectiveRadiusMeters: radius)
        }

        // Nearest-first, capped to the batch size. Overflow stays pending.
        entries.sort { $0.distanceMeters < $1.distanceMeters }
        let emitted = Array(entries.prefix(config.maxNotificationsPerBatch))

        for event in emitted {
            newState.places[event.id, default: PlaceProximityState()].wasInside = true
            newState.places[event.id]?.lastNotifiedAt = now
        }
        if !emitted.isEmpty {
            newState.lastNotificationAt = now
        }

        return ProximityOutcome(events: emitted, state: newState, effectiveRadiusMeters: radius)
    }
}
