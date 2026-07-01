import XCTest
@testable import SavedPlacesCore

final class SpatialIndexTests: XCTestCase {
    private func place(_ lat: Double, _ lon: Double) -> IndexedPlace {
        IndexedPlace(id: UUID(), coordinate: Coordinate(latitude: lat, longitude: lon))
    }

    func testFindsNearbyAndExcludesFar() {
        let index = SpatialIndex()
        let center = Coordinate(latitude: 51.5000, longitude: -0.1200)

        let near = place(51.5010, -0.1200)   // ~111 m north
        let mid  = place(51.5040, -0.1200)   // ~445 m north
        let far  = place(51.5200, -0.1200)   // ~2.2 km north
        index.build(from: [near, mid, far])

        let within500 = index.nearby(to: center, radiusMeters: 500)
        let ids = within500.map { $0.place.id }
        XCTAssertTrue(ids.contains(near.id))
        XCTAssertTrue(ids.contains(mid.id))
        XCTAssertFalse(ids.contains(far.id))
    }

    func testResultsSortedNearestFirst() {
        let index = SpatialIndex()
        let center = Coordinate(latitude: 51.5000, longitude: -0.1200)
        let far  = place(51.5040, -0.1200)
        let near = place(51.5010, -0.1200)
        index.build(from: [far, near])

        let results = index.nearby(to: center, radiusMeters: 1000)
        XCTAssertEqual(results.first?.place.id, near.id)
        XCTAssertLessThan(results[0].distanceMeters, results[1].distanceMeters)
    }

    func testHandlesCellBoundaryViaNeighbours() {
        // Put the query point and target on opposite sides of a geohash boundary
        // by searching many offsets; the neighbour grid must still find them.
        let index = SpatialIndex()
        let center = Coordinate(latitude: 51.5000, longitude: -0.1200)
        var found = true
        for i in 0..<50 {
            let delta = 0.0009 + Double(i) * 0.00001 // ~100 m, nudged across boundaries
            let target = place(center.latitude + delta, center.longitude)
            index.build(from: [target])
            let results = index.nearby(to: center, radiusMeters: 300)
            if !results.contains(where: { $0.place.id == target.id }) { found = false }
        }
        XCTAssertTrue(found, "boundary-straddling points must be found via neighbour cells")
    }

    func testScalesToManyPlaces() {
        let index = SpatialIndex()
        var places: [IndexedPlace] = []
        // 10,000 places scattered across a wide area.
        for _ in 0..<10_000 {
            let lat = Double.random(in: 50...52)
            let lon = Double.random(in: -1...1)
            places.append(place(lat, lon))
        }
        // Guarantee one very close hit.
        let target = place(51.5001, -0.1200)
        places.append(target)
        index.build(from: places)

        let start = Date()
        let results = index.nearby(to: Coordinate(latitude: 51.5000, longitude: -0.1200), radiusMeters: 500)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertTrue(results.contains { $0.place.id == target.id })
        XCTAssertLessThan(elapsed, 0.1, "nearby query should stay well under 100 ms")
    }
}
