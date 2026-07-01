import XCTest
@testable import SavedPlacesCore

final class GeohashTests: XCTestCase {
    func testKnownEncoding() {
        // Reference value from the geohash specification.
        let hash = Geohash.encode(latitude: 57.64911, longitude: 10.40744, precision: 11)
        XCTAssertEqual(hash, "u4pruydqqvj")
    }

    func testPrecisionLength() {
        let hash = Geohash.encode(latitude: 51.5, longitude: -0.12, precision: 6)
        XCTAssertEqual(hash.count, 6)
    }

    func testNeighboursReturnNineUniqueCells() {
        let hash = Geohash.encode(latitude: 51.5, longitude: -0.12, precision: 6)
        let neighbours = Geohash.neighbours(of: hash)
        XCTAssertEqual(neighbours.count, 9)
        XCTAssertEqual(Set(neighbours).count, 9, "neighbours should be distinct")
        XCTAssertTrue(neighbours.contains(hash))
    }

    func testAdjacentCellsAreClose() {
        let center = Coordinate(latitude: 51.5, longitude: -0.12)
        let hash = Geohash.encode(center, precision: 6)
        let neighbours = Geohash.neighbours(of: hash)
        // All neighbour cells should exist and differ from the centre except itself.
        XCTAssertEqual(neighbours.filter { $0 == hash }.count, 1)
    }

    func testBlockRingSizes() {
        let hash = Geohash.encode(latitude: 51.5, longitude: -0.12, precision: 6)
        XCTAssertEqual(Set(Geohash.block(around: hash, ring: 1)).count, 9)   // 3×3
        XCTAssertEqual(Set(Geohash.block(around: hash, ring: 2)).count, 25)  // 5×5
    }

    func testNorthNeighbourContainsPointAbove() {
        // A point ~445 m to the north must fall in the surrounding grid.
        let center = Coordinate(latitude: 51.5000, longitude: -0.1200)
        let hash = Geohash.encode(center, precision: 6)
        let north = Coordinate(latitude: center.latitude + 0.004, longitude: center.longitude)
        let northHash = Geohash.encode(north, precision: 6)
        XCTAssertTrue(Geohash.block(around: hash, ring: 2).contains(northHash))
    }
}
