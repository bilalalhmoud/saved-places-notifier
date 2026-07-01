import Foundation
import SavedPlacesCore

/// Bridges picked files to `TakeoutImporter`. Supports the individual files a
/// Google Takeout export contains once unzipped: `.json` / `.geojson`
/// (GeoJSON `FeatureCollection`, preferred) and `.csv` list exports.
enum ImportService {
    enum ImportError: Error, LocalizedError {
        case unreadable
        case unsupportedType(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "The file could not be read."
            case .unsupportedType(let ext): return "Unsupported file type: .\(ext). Import a .json, .geojson, or .csv from your Google Takeout export."
            }
        }
    }

    /// Imports a single Takeout file, deriving the list/category name from the
    /// file name (e.g. "London Restaurants.json" → "London Restaurants").
    static func importFile(at url: URL) throws -> [PlaceRecord] {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let listName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()

        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }

        switch ext {
        case "json", "geojson":
            return try TakeoutImporter.importGeoJSON(data: data, listName: listName)
        case "csv":
            guard let text = String(data: data, encoding: .utf8) else { throw ImportError.unreadable }
            return TakeoutImporter.importCSV(text: text, listName: listName)
        default:
            // Fall back to sniffing the content for a FeatureCollection.
            if let records = try? TakeoutImporter.importGeoJSON(data: data, listName: listName) {
                return records
            }
            throw ImportError.unsupportedType(ext)
        }
    }
}
