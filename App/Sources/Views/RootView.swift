import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "location.fill") }
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }
            ListsView()
                .tabItem { Label("Lists", systemImage: "list.bullet") }
            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .sheet(item: Binding(
            get: { model.selectedPlaceID.map(IdentifiedID.init) },
            set: { model.selectedPlaceID = $0?.id }
        )) { wrapper in
            if let place = model.place(for: wrapper.id) {
                NavigationStack { PlaceDetailView(place: place) }
            }
        }
    }
}

/// Wraps a `UUID` so it can drive a `.sheet(item:)`.
struct IdentifiedID: Identifiable {
    let id: UUID
}
