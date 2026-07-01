import Foundation
import SwiftData
import SavedPlacesCore

/// SwiftData-backed persistent record for a saved place.
///
/// This mirrors `SavedPlacesCore.PlaceRecord` but adds the persisted
/// notification/visit bookkeeping used by the app.
@Model
final class SavedPlace {
    @Attribute(.unique) var id: UUID
    var googlePlaceID: String?
    var title: String
    var latitude: Double
    var longitude: Double
    var address: String?
    var category: String?
    var notes: String?
    var tags: [String]
    var dateSaved: Date?
    var lastNotification: Date?
    var lastVisited: Date?
    var favourite: Bool
    var icon: String?

    init(
        id: UUID = UUID(),
        googlePlaceID: String? = nil,
        title: String,
        latitude: Double,
        longitude: Double,
        address: String? = nil,
        category: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        dateSaved: Date? = nil,
        lastNotification: Date? = nil,
        lastVisited: Date? = nil,
        favourite: Bool = false,
        icon: String? = nil
    ) {
        self.id = id
        self.googlePlaceID = googlePlaceID
        self.title = title
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.category = category
        self.notes = notes
        self.tags = tags
        self.dateSaved = dateSaved
        self.lastNotification = lastNotification
        self.lastVisited = lastVisited
        self.favourite = favourite
        self.icon = icon
    }

    convenience init(record: PlaceRecord) {
        self.init(
            id: record.id,
            googlePlaceID: record.googlePlaceID,
            title: record.title,
            latitude: record.coordinate.latitude,
            longitude: record.coordinate.longitude,
            address: record.address,
            category: record.category,
            notes: record.notes,
            tags: record.tags,
            dateSaved: record.dateSaved
        )
    }

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
    var indexed: IndexedPlace { IndexedPlace(id: id, coordinate: coordinate) }

    /// Deep link that opens this place in Google Maps (app if installed, else web).
    var googleMapsURL: URL? {
        if let placeID = googlePlaceID, placeID.allSatisfy({ $0.isNumber }) {
            return URL(string: "comgooglemaps://?cid=\(placeID)")
        }
        let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)&query_place_id=\(query)")
    }

    /// Apple Maps / Google navigation deep link starting turn-by-turn directions.
    var navigationURL: URL? {
        URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(latitude),\(longitude)")
    }
}
