import SwiftUI

/// Small presentation helpers shared across views.
enum Format {
    /// Human-friendly distance: "230 m" or "1.4 km".
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }
}

extension String {
    /// A stable colour derived from a category name, for map pins and chips.
    var categoryColor: Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo, .mint, .brown]
        let hash = self.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return palette[hash % palette.count]
    }

    /// A best-effort SF Symbol for a category.
    var categorySymbol: String {
        let lower = lowercased()
        if lower.contains("coffee") || lower.contains("cafe") { return "cup.and.saucer.fill" }
        if lower.contains("restaurant") || lower.contains("food") || lower.contains("eat") { return "fork.knife" }
        if lower.contains("pub") || lower.contains("bar") || lower.contains("drink") { return "wineglass.fill" }
        if lower.contains("hotel") || lower.contains("stay") { return "bed.double.fill" }
        if lower.contains("museum") || lower.contains("art") { return "building.columns.fill" }
        if lower.contains("hik") || lower.contains("park") || lower.contains("nature") { return "figure.hiking" }
        if lower.contains("shop") || lower.contains("store") { return "bag.fill" }
        if lower.contains("wish") || lower.contains("want") { return "star.fill" }
        return "mappin.circle.fill"
    }
}
