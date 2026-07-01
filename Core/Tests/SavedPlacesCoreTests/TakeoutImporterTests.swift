import XCTest
@testable import SavedPlacesCore

final class TakeoutImporterTests: XCTestCase {

    func testImportsGeoJSONFeatureCollection() throws {
        let json = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": { "type": "Point", "coordinates": [-0.1657, 51.4989] },
              "properties": {
                "date": "2023-05-01T12:00:00Z",
                "google_maps_url": "http://maps.google.com/?cid=123456789",
                "Location": {
                  "Business Name": "Dishoom Kensington",
                  "Address": "4 Derry St, London W8 5SE, UK",
                  "Country Code": "GB"
                },
                "Comment": "Best breakfast naan"
              }
            }
          ]
        }
        """
        let records = try TakeoutImporter.importGeoJSON(data: Data(json.utf8), listName: "London Restaurants")
        XCTAssertEqual(records.count, 1)
        let place = try XCTUnwrap(records.first)
        XCTAssertEqual(place.title, "Dishoom Kensington")
        XCTAssertEqual(place.category, "London Restaurants")
        XCTAssertEqual(place.address, "4 Derry St, London W8 5SE, UK")
        XCTAssertEqual(place.notes, "Best breakfast naan")
        XCTAssertEqual(place.googlePlaceID, "123456789")
        XCTAssertEqual(place.coordinate.latitude, 51.4989, accuracy: 0.0001)
        XCTAssertEqual(place.coordinate.longitude, -0.1657, accuracy: 0.0001)
        XCTAssertNotNil(place.dateSaved)
    }

    func testSkipsInvalidGeometry() throws {
        let json = """
        {
          "type": "FeatureCollection",
          "features": [
            { "type": "Feature", "geometry": { "type": "Point", "coordinates": [0, 0] }, "properties": {} },
            { "type": "Feature", "geometry": null, "properties": {} }
          ]
        }
        """
        let records = try TakeoutImporter.importGeoJSON(data: Data(json.utf8), listName: "Test")
        XCTAssertTrue(records.isEmpty, "null-island and missing geometry must be skipped")
    }

    func testRejectsNonFeatureCollection() {
        let json = "{ \"type\": \"Something\", \"features\": [] }"
        XCTAssertThrowsError(try TakeoutImporter.importGeoJSON(data: Data(json.utf8), listName: "x")) { error in
            XCTAssertEqual(error as? TakeoutImporter.ImportError, .notAFeatureCollection)
        }
    }

    func testExtractsCoordinateFromURLPatterns() {
        let atPattern = TakeoutImporter.coordinate(fromURL: "https://www.google.com/maps/place/X/@51.4989,-0.1657,17z")
        XCTAssertEqual(atPattern?.latitude ?? 0, 51.4989, accuracy: 0.0001)

        let dPattern = TakeoutImporter.coordinate(fromURL: "https://maps.google.com/?...!3d51.5!4d-0.12")
        XCTAssertEqual(dPattern?.longitude ?? 0, -0.12, accuracy: 0.0001)

        let qPattern = TakeoutImporter.coordinate(fromURL: "https://maps.google.com/?q=48.8566,2.3522")
        XCTAssertEqual(qPattern?.latitude ?? 0, 48.8566, accuracy: 0.0001)
    }

    func testImportsCSVWithURLCoordinates() {
        let csv = """
        Title,Note,URL
        "Eiffel Tower","Sunset view","https://www.google.com/maps/place/Eiffel/@48.8584,2.2945,17z"
        "No Coordinates","x","https://maps.google.com/?cid=999"
        """
        let records = TakeoutImporter.importCSV(text: csv, listName: "Paris")
        XCTAssertEqual(records.count, 1, "only rows with usable coordinates are imported")
        XCTAssertEqual(records.first?.title, "Eiffel Tower")
        XCTAssertEqual(records.first?.category, "Paris")
        XCTAssertEqual(records.first?.coordinate.latitude ?? 0, 48.8584, accuracy: 0.0001)
    }

    func testCSVParserHandlesQuotedCommas() {
        let rows = TakeoutImporter.parseCSV("a,\"b,c\",d\n1,2,3")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["a", "b,c", "d"])
        XCTAssertEqual(rows[1], ["1", "2", "3"])
    }
}
