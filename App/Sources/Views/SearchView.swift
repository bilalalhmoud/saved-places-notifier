import SwiftUI
import SwiftData

struct SearchView: View {
    @Query private var places: [SavedPlace]
    @State private var query = ""

    private var results: [SavedPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return [] }
        return places.filter { place in
            place.title.lowercased().contains(trimmed) ||
            (place.address?.lowercased().contains(trimmed) ?? false) ||
            (place.notes?.lowercased().contains(trimmed) ?? false) ||
            (place.category?.lowercased().contains(trimmed) ?? false) ||
            place.tags.contains { $0.lowercased().contains(trimmed) }
        }
        .sorted { $0.title < $1.title }
    }

    var body: some View {
        NavigationStack {
            List(results) { place in
                NavigationLink { PlaceDetailView(place: place) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.title)
                        HStack(spacing: 6) {
                            if let category = place.category {
                                Text(category).font(.caption).foregroundStyle(place.category!.categoryColor)
                            }
                            if let address = place.address {
                                Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Name, area, tag, notes or category")
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView("Search your places", systemImage: "magnifyingglass", description: Text("Find saved places by name, area, tag, notes or category."))
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}
