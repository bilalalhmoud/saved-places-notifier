import SwiftUI
import MapKit

struct PlaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @Bindable var place: SavedPlace

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    var body: some View {
        List {
            Section {
                Map(initialPosition: .region(region)) {
                    Marker(place.title, coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                        .tint((place.category ?? "Saved").categoryColor)
                }
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if let category = place.category {
                    LabeledContent("List", value: category)
                }
                if let address = place.address {
                    LabeledContent("Address", value: address)
                }
                if let notes = place.notes, !notes.isEmpty {
                    LabeledContent("Notes", value: notes)
                }
                if let saved = place.dateSaved {
                    LabeledContent("Saved", value: saved.formatted(date: .abbreviated, time: .omitted))
                }
                if let visited = place.lastVisited {
                    LabeledContent("Last visited", value: visited.formatted(date: .abbreviated, time: .omitted))
                }
            }

            Section {
                Button {
                    if let url = place.navigationURL { openURL(url) }
                } label: { Label("Start navigation", systemImage: "location.north.line.fill") }

                Button {
                    if let url = place.googleMapsURL { openURL(url) }
                } label: { Label("Open in Google Maps", systemImage: "map") }

                Button {
                    model.markVisited(place)
                } label: { Label("Mark as visited", systemImage: "checkmark.circle") }
            }
        }
        .navigationTitle(place.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.toggleFavourite(place)
                } label: {
                    Image(systemName: place.favourite ? "star.fill" : "star")
                        .foregroundStyle(place.favourite ? .yellow : .primary)
                }
                .accessibilityLabel("Toggle favourite")
            }
        }
    }
}
