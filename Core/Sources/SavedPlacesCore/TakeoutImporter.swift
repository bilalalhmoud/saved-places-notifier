import Foundation

/// Imports saved places from a Google Takeout export.
///
/// Google Takeout exports *Saved* lists in two shapes:
/// 1. **GeoJSON** (`Saved Places.json`, or each list as a `.geojson`) — a
///    `FeatureCollection` of `Point` features that include coordinates. This is
///    the preferred, lossless source.
/// 2. **CSV** (e.g. `Favourite places.csv`) — columns `Title, Note, URL`. These
///    do not carry coordinates directly, so we best-effort extract them from the
///    Google Maps URL.
public enum TakeoutImporter {

    public enum ImportError: Error, Equatable {
        case invalidEncoding
        case notAFeatureCollection
        case emptyFile
    }

    // MARK: GeoJSON

    private struct FeatureCollection: Decodable {
        let type: String
        let features: [Feature]
    }

    private struct Feature: Decodable {
        let geometry: Geometry?
        let properties: Properties?
    }

    private struct Geometry: Decodable {
        let type: String
        let coordinates: [Double] // [longitude, latitude]
    }

    private struct Properties: Decodable {
        let date: String?
        let googleMapsURL: String?
        let location: Location?
        let comment: String?
        let title: String?

        enum CodingKeys: String, CodingKey {
            case date
            case googleMapsURL = "google_maps_url"
            case location = "Location"
            case comment = "Comment"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: DynamicKey.self)
            // Case-insensitive, tolerant lookup because Takeout casing varies.
            func value(_ keys: String...) -> String? {
                for key in keys {
                    if let dk = DynamicKey(stringValue: key),
                       let s = try? c.decode(String.self, forKey: dk) {
                        return s
                    }
                }
                return nil
            }
            self.date = value("date", "Date", "Published", "Updated")
            self.googleMapsURL = value("google_maps_url", "Google Maps URL", "url")
            self.comment = value("Comment", "comment", "Note", "note")
            self.title = value("Title", "title")
            if let lk = DynamicKey(stringValue: "Location") {
                self.location = try? c.decode(Location.self, forKey: lk)
            } else {
                self.location = nil
            }
        }
    }

    private struct Location: Decodable {
        let name: String?
        let address: String?
        let countryCode: String?

        enum CodingKeys: String, CodingKey {
            case name = "Business Name"
            case address = "Address"
            case countryCode = "Country Code"
            case nameLower = "name"
            case addressLower = "address"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.name = (try? c.decode(String.self, forKey: .name))
                ?? (try? c.decode(String.self, forKey: .nameLower))
            self.address = (try? c.decode(String.self, forKey: .address))
                ?? (try? c.decode(String.self, forKey: .addressLower))
            self.countryCode = try? c.decode(String.self, forKey: .countryCode)
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    /// Parses a GeoJSON Takeout export. `listName` becomes the place category.
    public static func importGeoJSON(data: Data, listName: String) throws -> [PlaceRecord] {
        let decoder = JSONDecoder()
        let collection: FeatureCollection
        do {
            collection = try decoder.decode(FeatureCollection.self, from: data)
        } catch {
            throw ImportError.notAFeatureCollection
        }
        guard collection.type == "FeatureCollection" else {
            throw ImportError.notAFeatureCollection
        }

        let isoFormatter = ISO8601DateFormatter()
        var records: [PlaceRecord] = []

        for feature in collection.features {
            guard let geometry = feature.geometry,
                  geometry.type == "Point",
                  geometry.coordinates.count >= 2 else { continue }

            let coordinate = Coordinate(
                latitude: geometry.coordinates[1],
                longitude: geometry.coordinates[0]
            )
            guard coordinate.isValid else { continue }

            let props = feature.properties
            let title = props?.location?.name
                ?? props?.title
                ?? props?.location?.address
                ?? "Saved place"
            let date = props?.date.flatMap { isoFormatter.date(from: $0) }

            records.append(
                PlaceRecord(
                    googlePlaceID: props?.googleMapsURL.flatMap(placeID(fromURL:)),
                    title: title,
                    coordinate: coordinate,
                    address: props?.location?.address,
                    category: listName,
                    notes: props?.comment,
                    dateSaved: date
                )
            )
        }

        if records.isEmpty && collection.features.isEmpty {
            throw ImportError.emptyFile
        }
        return records
    }

    // MARK: CSV

    /// Parses a Takeout list CSV (`Title, Note, URL`). Coordinates are extracted
    /// from the Maps URL where possible; rows without usable coordinates are
    /// skipped.
    public static func importCSV(text: String, listName: String) -> [PlaceRecord] {
        let rows = parseCSV(text)
        guard let header = rows.first else { return [] }

        let lower = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let titleIdx = lower.firstIndex(where: { $0.contains("title") || $0.contains("name") }) ?? 0
        let noteIdx = lower.firstIndex(where: { $0.contains("note") || $0.contains("comment") })
        let urlIdx = lower.firstIndex(where: { $0.contains("url") || $0.contains("link") })

        var records: [PlaceRecord] = []
        for row in rows.dropFirst() {
            guard row.count > titleIdx else { continue }
            let title = row[titleIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }

            let url = urlIdx.flatMap { $0 < row.count ? row[$0] : nil }
            guard let url, let coordinate = coordinate(fromURL: url) else { continue }

            let note = noteIdx.flatMap { $0 < row.count ? row[$0] : nil }
            records.append(
                PlaceRecord(
                    googlePlaceID: placeID(fromURL: url),
                    title: title,
                    coordinate: coordinate,
                    category: listName,
                    notes: note?.isEmpty == true ? nil : note
                )
            )
        }
        return records
    }

    // MARK: URL parsing

    /// Extracts a coordinate from common Google Maps URL patterns.
    public static func coordinate(fromURL urlString: String) -> Coordinate? {
        // Pattern: @lat,lon (…/@51.4989,-0.1657,17z)
        if let coord = firstMatch(in: urlString, pattern: "@(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)") {
            return coord
        }
        // Pattern: !3dLAT!4dLON
        if let lat = firstDouble(in: urlString, pattern: "!3d(-?\\d+\\.\\d+)"),
           let lon = firstDouble(in: urlString, pattern: "!4d(-?\\d+\\.\\d+)") {
            let c = Coordinate(latitude: lat, longitude: lon)
            if c.isValid { return c }
        }
        // Pattern: ?q=lat,lon  or  &query=lat,lon  or  ll=lat,lon
        if let coord = firstMatch(in: urlString, pattern: "(?:q|query|ll|destination)=(-?\\d+\\.\\d+),(-?\\d+\\.\\d+)") {
            return coord
        }
        return nil
    }

    /// Extracts a stable place identifier (cid / ftid / place_id) from a Maps URL.
    public static func placeID(fromURL urlString: String) -> String? {
        for pattern in ["cid=([0-9]+)", "ftid=([^&]+)", "place_id=([^&]+)", "1s([0-9a-fx:]+)"] {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)),
               let range = Range(match.range(at: 1), in: urlString) {
                return String(urlString[range])
            }
        }
        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> Coordinate? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let latRange = Range(match.range(at: 1), in: text),
              let lonRange = Range(match.range(at: 2), in: text),
              let lat = Double(text[latRange]),
              let lon = Double(text[lonRange]) else { return nil }
        let c = Coordinate(latitude: lat, longitude: lon)
        return c.isValid ? c : nil
    }

    private static func firstDouble(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    // MARK: Minimal RFC-4180 CSV parser (handles quoted fields & embedded commas)

    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let ch = nextChar() {
            if inQuotes {
                if ch == "\"" {
                    if let n = nextChar() {
                        if n == "\"" { field.append("\"") } // escaped quote
                        else { inQuotes = false; pending = n }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",":
                    record.append(field); field = ""
                case "\n":
                    record.append(field); field = ""
                    rows.append(record); record = []
                case "\r":
                    break // ignore; newline handled by \n
                default:
                    field.append(ch)
                }
            }
        }
        // flush trailing field/record
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            rows.append(record)
        }
        return rows.filter { !($0.count == 1 && $0[0].isEmpty) }
    }
}
