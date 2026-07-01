import XCTest
import SavedPlacesCore
@testable import SavedPlacesNotifier

final class SavedPlaceMappingTests: XCTestCase {
    func testRecordToModelMapping() {
        let record = PlaceRecord(
            googlePlaceID: "123",
            title: "Dishoom",
            coordinate: Coordinate(latitude: 51.4989, longitude: -0.1657),
            address: "4 Derry St",
            category: "London Restaurants",
            notes: "Naan"
        )
        let place = SavedPlace(record: record)
        XCTAssertEqual(place.title, "Dishoom")
        XCTAssertEqual(place.latitude, 51.4989, accuracy: 0.0001)
        XCTAssertEqual(place.category, "London Restaurants")
        XCTAssertEqual(place.indexed.id, record.id)
    }

    func testGoogleMapsURLUsesCIDForNumericID() {
        let place = SavedPlace(title: "X", latitude: 1, longitude: 2)
        place.googlePlaceID = "987654321"
        XCTAssertEqual(place.googleMapsURL?.scheme, "comgooglemaps")
    }

    func testNavigationURLBuilt() {
        let place = SavedPlace(title: "X", latitude: 51.5, longitude: -0.12)
        XCTAssertTrue(place.navigationURL?.absoluteString.contains("destination=51.5,-0.12") ?? false)
    }
}
