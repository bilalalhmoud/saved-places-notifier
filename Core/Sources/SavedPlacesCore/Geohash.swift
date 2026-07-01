import Foundation

/// Geohash encoding plus neighbour/grid helpers used to build a spatial index.
///
/// A geohash is a base-32 string where each additional character narrows the
/// covered rectangle. By bucketing saved places into geohash cells we can find
/// nearby candidates by only inspecting a small grid of cells instead of
/// scanning every place — this is what lets the app scale to tens of thousands
/// of places while staying under 100 ms per query.
public enum Geohash {
    private static let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    private static let bits = [16, 8, 4, 2, 1]

    // MARK: Encoding

    /// Encodes a coordinate to a geohash string of the requested precision.
    public static func encode(latitude: Double, longitude: Double, precision: Int) -> String {
        var latInterval = (-90.0, 90.0)
        var lonInterval = (-180.0, 180.0)
        var geohash = ""
        var isEven = true
        var bit = 0
        var ch = 0

        while geohash.count < precision {
            if isEven {
                let mid = (lonInterval.0 + lonInterval.1) / 2
                if longitude >= mid {
                    ch |= bits[bit]
                    lonInterval.0 = mid
                } else {
                    lonInterval.1 = mid
                }
            } else {
                let mid = (latInterval.0 + latInterval.1) / 2
                if latitude >= mid {
                    ch |= bits[bit]
                    latInterval.0 = mid
                } else {
                    latInterval.1 = mid
                }
            }

            isEven.toggle()
            if bit < 4 {
                bit += 1
            } else {
                geohash.append(base32[ch])
                bit = 0
                ch = 0
            }
        }
        return geohash
    }

    public static func encode(_ coordinate: Coordinate, precision: Int) -> String {
        encode(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: precision)
    }

    // MARK: Neighbours

    private enum Direction: String, CaseIterable {
        case north, south, east, west
    }

    // Lookup tables from the canonical geohash neighbour algorithm.
    // Each entry is [oddLength, evenLength].
    private static let neighbourTable: [Direction: [String]] = [
        .north: ["p0r21436x8zb9dcf5h7kjnmqesgutwvy", "bc01fg45238967deuvhjyznpkmstqrwx"],
        .south: ["14365h7k9dcfesgujnmqp0r2twvyx8zb", "238967debc01fg45kmstqrwxuvhjyznp"],
        .east:  ["bc01fg45238967deuvhjyznpkmstqrwx", "p0r21436x8zb9dcf5h7kjnmqesgutwvy"],
        .west:  ["238967debc01fg45kmstqrwxuvhjyznp", "14365h7k9dcfesgujnmqp0r2twvyx8zb"]
    ]

    private static let borderTable: [Direction: [String]] = [
        .north: ["prxz", "bcfguvyz"],
        .south: ["028b", "0145hjnp"],
        .east:  ["bcfguvyz", "prxz"],
        .west:  ["0145hjnp", "028b"]
    ]

    private static func adjacent(_ hash: String, _ direction: Direction) -> String {
        let hash = hash.lowercased()
        guard let lastChar = hash.last else { return hash }
        let typeIndex = (hash.count % 2 == 1) ? 0 : 1 // odd length -> 0, even -> 1
        var base = String(hash.dropLast())

        let border = borderTable[direction]![typeIndex]
        if border.contains(lastChar) {
            base = adjacent(base, direction)
        }

        let neighbours = Array(neighbourTable[direction]![typeIndex])
        guard let idx = neighbours.firstIndex(of: lastChar) else { return base }
        base.append(base32[idx])
        return base
    }

    /// Returns the 9-cell block (self + 8 neighbours) around `hash`.
    public static func neighbours(of hash: String) -> [String] {
        let n = adjacent(hash, .north)
        let s = adjacent(hash, .south)
        let e = adjacent(hash, .east)
        let w = adjacent(hash, .west)
        return [
            hash,
            n, s, e, w,
            adjacent(n, .east), adjacent(n, .west),
            adjacent(s, .east), adjacent(s, .west)
        ]
    }

    /// Returns the `(2*ring+1)²` block of geohash cells centred on `hash`.
    /// `ring == 1` yields the classic 3×3 neighbourhood.
    public static func block(around hash: String, ring: Int) -> [String] {
        guard ring > 0 else { return [hash] }

        // Walk to the north-west corner of the block.
        var corner = hash
        for _ in 0..<ring { corner = adjacent(corner, .north) }
        for _ in 0..<ring { corner = adjacent(corner, .west) }

        var result: [String] = []
        let side = ring * 2 + 1
        var rowStart = corner
        for _ in 0..<side {
            var cell = rowStart
            for _ in 0..<side {
                result.append(cell)
                cell = adjacent(cell, .east)
            }
            rowStart = adjacent(rowStart, .south)
        }
        return result
    }
}
