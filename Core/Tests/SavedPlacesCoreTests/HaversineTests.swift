import XCTest
@testable import SavedPlacesCore

final class HaversineTests: XCTestCase {
    func testKnownDistanceLondonToParis() {
        // London (51.5074, -0.1278) to Paris (48.8566, 2.3522) ≈ 343 km.
        let london = Coordinate(latitude: 51.5074, longitude: -0.1278)
        let paris = Coordinate(latitude: 48.8566, longitude: 2.3522)
        let distance = Haversine.distance(london, paris)
        XCTAssertEqual(distance, 343_000, accuracy: 5_000)
    }

    func testZeroDistance() {
        let point = Coordinate(latitude: 40, longitude: -3)
        XCTAssertEqual(Haversine.distance(point, point), 0, accuracy: 0.001)
    }

    func testSymmetry() {
        let a = Coordinate(latitude: 10, longitude: 20)
        let b = Coordinate(latitude: -5, longitude: 45)
        XCTAssertEqual(Haversine.distance(a, b), Haversine.distance(b, a), accuracy: 0.001)
    }

    func testShortDistanceAccuracy() {
        // Two points ~111 m apart in latitude (0.001°).
        let a = Coordinate(latitude: 51.5000, longitude: -0.1000)
        let b = Coordinate(latitude: 51.5009, longitude: -0.1000)
        XCTAssertEqual(Haversine.distance(a, b), 100, accuracy: 3)
    }
}
