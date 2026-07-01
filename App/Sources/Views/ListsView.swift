import SwiftUI
import SwiftData

struct ListsView: View {
    @EnvironmentObject private var model: AppModel
    @Query private var places: [SavedPlace]

    private var byCategory: [(name: String, places: [SavedPlace])] {
        Dictionary(grouping: places) { $0.category ?? "Uncategorised" }
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.name < $1.name }
    }

    private var favourites: [SavedPlace] { places.filter { $0.favourite } }
    private var recentlyVisited: [SavedPlace] {
        places.filter { $0.lastVisited != nil }.sorted { ($0.lastVisited ?? .distantPast) > ($1.lastVisited ?? .distantPast) }
    }
    private var recentlyNearby: [SavedPlace] {
        model.nearby.compactMap { model.place(for: $0.place.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Smart lists") {
                    smartLink("Favourites", systemImage: "star.fill", color: .yellow, items: favourites)
                    smartLink("Recently nearby", systemImage: "location.circle.fill", color: .blue, items: recentlyNearby)
                    smartLink("Recently visited", systemImage: "checkmark.circle.fill", color: .green, items: recentlyVisited)
                }

                Section("Lists") {
                    ForEach(byCategory, id: \.name) { group in
                        NavigationLink {
                            PlaceListView(title: group.name, places: group.places)
                        } label: {
                            Label {
                                HStack {
                                    Text(group.name)
                                    Spacer()
                                    Text("\(group.places.count)").foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: group.name.categorySymbol)
                                    .foregroundStyle(group.name.categoryColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Lists")
            .overlay {
                if places.isEmpty {
                    ContentUnavailableView("No lists yet", systemImage: "list.bullet", description: Text("Import your saved places to see your lists."))
                }
            }
        }
    }

    @ViewBuilder
    private func smartLink(_ title: String, systemImage: String, color: Color, items: [SavedPlace]) -> some View {
        NavigationLink {
            PlaceListView(title: title, places: items)
        } label: {
            Label {
                HStack { Text(title); Spacer(); Text("\(items.count)").foregroundStyle(.secondary) }
            } icon: {
                Image(systemName: systemImage).foregroundStyle(color)
            }
        }
    }
}

/// A reusable list of places (used by categories and smart lists).
struct PlaceListView: View {
    let title: String
    let places: [SavedPlace]

    var body: some View {
        List(places) { place in
            NavigationLink { PlaceDetailView(place: place) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.title)
                    if let address = place.address {
                        Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle(title)
        .overlay {
            if places.isEmpty {
                ContentUnavailableView("Empty", systemImage: "tray", description: Text("Nothing here yet."))
            }
        }
    }
}
