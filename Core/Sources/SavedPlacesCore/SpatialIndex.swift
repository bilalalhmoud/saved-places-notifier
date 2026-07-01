import Foundation

/// A minimal entry stored in the spatial index: just enough to locate a place.
public struct IndexedPlace: Equatable, Hashable, Sendable {
    public let id: UUID
    public let coordinate: Coordinate

    public init(id: UUID, coordinate: Coordinate) {
        self.id = id
        self.coordinate = coordinate
    }
}

/// A candidate returned by a proximity query, together with its precise distance.
public struct NearbyResult: Equatable, Sendable {
    public let place: IndexedPlace
    public let distanceMeters: Double

    public init(place: IndexedPlace, distanceMeters: Double) {
        self.place = place
        self.distanceMeters = distanceMeters
    }
}

/// A geohash-bucketed spatial index.
///
/// Places are bucketed by a fixed-precision geohash. Queries only inspect the
/// grid of cells that can possibly contain a point within the search radius,
/// then run a precise Haversine filter on that small candidate set.
public final class SpatialIndex {
    /// Geohash precision used for bucketing. Precision 6 ≈ 1.2 km × 0.6 km cells,
    /// a good balance for city-scale proximity searches.
    public let precision: Int

    /// Smallest cell dimension (metres) at `precision`, used to size the grid.
    private let cellMinDimension: Double

    private var buckets: [String: [IndexedPlace]] = [:]
    private(set) public var count = 0

    public init(precision: Int = 6) {
        self.precision = precision
        self.cellMinDimension = SpatialIndex.latitudeCellHeightMeters(precision: precision)
    }

    // MARK: Building

    public func insert(_ place: IndexedPlace) {
        let hash = Geohash.encode(place.coordinate, precision: precision)
        buckets[hash, default: []].append(place)
        count += 1
    }

    public func build(from places: [IndexedPlace]) {
        buckets.removeAll(keepingCapacity: true)
        count = 0
        for place in places { insert(place) }
    }

    public func removeAll() {
        buckets.removeAll(keepingCapacity: true)
        count = 0
    }

    // MARK: Querying

    /// Returns candidate places within `radiusMeters`, sorted nearest-first.
    public func nearby(to center: Coordinate, radiusMeters: Double) -> [NearbyResult] {
        guard radiusMeters > 0 else { return [] }

        // How many geohash cells (rings) we must expand to cover the radius.
        let ring = max(1, Int((radiusMeters / cellMinDimension).rounded(.up)))
        let centerHash = Geohash.encode(center, precision: precision)
        let cells = Set(Geohash.block(around: centerHash, ring: ring))

        var results: [NearbyResult] = []
        for cell in cells {
            guard let bucket = buckets[cell] else { continue }
            for place in bucket {
                let distance = Haversine.distance(center, place.coordinate)
                if distance <= radiusMeters {
                    results.append(NearbyResult(place: place, distanceMeters: distance))
                }
            }
        }
        results.sort { $0.distanceMeters < $1.distanceMeters }
        return results
    }

    // MARK: Geometry helpers

    /// Latitudinal height (metres) of a geohash cell at a given precision.
    /// This is the smaller, latitude-independent dimension used to size queries.
    static func latitudeCellHeightMeters(precision: Int) -> Double {
        // Latitude bits accumulated after `precision` base-32 characters.
        let latBits = (precision * 5) / 2
        let degrees = 180.0 / pow(2.0, Double(latBits))
        return degrees * 111_320.0
    }
}
