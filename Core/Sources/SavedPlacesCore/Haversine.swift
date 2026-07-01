import Foundation

/// Great-circle distance helpers. Used to compute the *precise* distance for the
/// small candidate set returned by the spatial index.
public enum Haversine {
    /// Mean Earth radius in metres.
    public static let earthRadiusMeters = 6_371_000.0

    /// Distance in metres between two coordinates using the Haversine formula.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180

        let sinDLat = sin(dLat / 2)
        let sinDLon = sin(dLon / 2)
        let h = sinDLat * sinDLat + cos(lat1) * cos(lat2) * sinDLon * sinDLon
        let c = 2 * atan2(sqrt(h), sqrt(max(0, 1 - h)))
        return earthRadiusMeters * c
    }
}
