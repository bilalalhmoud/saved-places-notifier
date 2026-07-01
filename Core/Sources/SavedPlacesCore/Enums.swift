import Foundation

/// How the user is currently moving. Drives the adaptive notification radius.
public enum TransportMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case walking
    case cycling
    case driving
    case transit
    case any

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .driving: return "Driving"
        case .transit: return "Public transport"
        case .any:     return "Any"
        }
    }

    /// Adaptive radius (metres) for this mode, derived from the user's base radius.
    /// Faster travel → larger radius so notifications arrive with enough lead time.
    public func radius(base: Double) -> Double {
        switch self {
        case .walking: return min(base, 300)
        case .cycling: return min(max(base, 400), 500)
        case .driving: return max(base, 900)
        case .transit: return max(min(base, 600), 500)
        case .any:     return base
        }
    }
}

/// Controls how often the same place may notify again.
public enum Cooldown: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Re-notify only after the user leaves and later returns to the radius.
    case untilLeave
    case oneHour
    case oneDay

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .untilLeave: return "Until I leave & return"
        case .oneHour:    return "At most once per hour"
        case .oneDay:     return "At most once per day"
        }
    }

    /// Minimum seconds between two notifications for the same place.
    /// `untilLeave` relies purely on the leave/return transition, hence 0.
    public var interval: TimeInterval {
        switch self {
        case .untilLeave: return 0
        case .oneHour:    return 3_600
        case .oneDay:     return 86_400
        }
    }
}
