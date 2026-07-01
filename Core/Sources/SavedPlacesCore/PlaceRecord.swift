import Foundation

/// A plain-value representation of a saved place. The app persists these via
/// SwiftData, but the core engine and importer work with this platform-neutral
/// struct so everything stays unit-testable.
public struct PlaceRecord: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var googlePlaceID: String?
    public var title: String
    public var coordinate: Coordinate
    public var address: String?
    public var category: String?
    public var notes: String?
    public var tags: [String]
    public var dateSaved: Date?

    public init(
        id: UUID = UUID(),
        googlePlaceID: String? = nil,
        title: String,
        coordinate: Coordinate,
        address: String? = nil,
        category: String? = nil,
        notes: String? = nil,
        tags: [String] = [],
        dateSaved: Date? = nil
    ) {
        self.id = id
        self.googlePlaceID = googlePlaceID
        self.title = title
        self.coordinate = coordinate
        self.address = address
        self.category = category
        self.notes = notes
        self.tags = tags
        self.dateSaved = dateSaved
    }

    public var indexed: IndexedPlace {
        IndexedPlace(id: id, coordinate: coordinate)
    }
}
