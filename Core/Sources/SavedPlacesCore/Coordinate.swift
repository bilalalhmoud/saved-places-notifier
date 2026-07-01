import Foundation

/// A lightweight, `Sendable` geographic coordinate used throughout the core
/// engine. Kept independent of Core Location so the logic is testable on any
/// platform (including Linux/macOS CI without a simulator).
public struct Coordinate: Equatable, Hashable, Codable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Returns `true` when both components are within valid WGS84 ranges.
    public var isValid: Bool {
        latitude >= -90 && latitude <= 90 &&
        longitude >= -180 && longitude <= 180 &&
        !(latitude == 0 && longitude == 0) // reject null-island placeholders
    }
}
