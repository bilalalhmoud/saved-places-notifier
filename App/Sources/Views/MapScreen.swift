import SwiftUI
import SwiftData
import MapKit

/// Full-screen map of every saved place with clustering and category colours.
struct MapScreen: View {
    @EnvironmentObject private var model: AppModel
    @Query private var places: [SavedPlace]
    @State private var selected: SavedPlace?

    var body: some View {
        NavigationStack {
            ClusteredMapView(places: places, selection: $selected)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Map")
                .navigationBarTitleDisplayMode(.inline)
                .sheet(item: $selected) { place in
                    NavigationStack { PlaceDetailView(place: place) }
                        .presentationDetents([.medium, .large])
                }
                .overlay(alignment: .top) {
                    if places.isEmpty {
                        Text("Import saved places to see them on the map")
                            .font(.footnote)
                            .padding(8)
                            .background(.thinMaterial, in: Capsule())
                            .padding(.top, 8)
                    }
                }
        }
    }
}

/// `MKMapView` wrapper: MapKit's built-in clustering keeps thousands of pins
/// smooth, which SwiftUI's `Map` does not do out of the box.
struct ClusteredMapView: UIViewRepresentable {
    let places: [SavedPlace]
    @Binding var selection: SavedPlace?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "place")
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Rebuild annotations only when the underlying set changes.
        if map.annotations.count - (map.showsUserLocation ? 1 : 0) != places.count {
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            map.addAnnotations(places.map(PlaceAnnotation.init))
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let parent: ClusteredMapView
        init(_ parent: ClusteredMapView) { self.parent = parent }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }

            if let cluster = annotation as? MKClusterAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster) as! MKMarkerAnnotationView
                view.markerTintColor = .systemGray
                view.glyphText = "\(cluster.memberAnnotations.count)"
                return view
            }

            guard let place = annotation as? PlaceAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place", for: place) as! MKMarkerAnnotationView
            view.clusteringIdentifier = "place"
            view.markerTintColor = UIColor((place.category ?? "Saved").categoryColor)
            view.glyphImage = UIImage(systemName: (place.category ?? "").categorySymbol)
            view.canShowCallout = true
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
            if let place = (view.annotation as? PlaceAnnotation)?.place {
                parent.selection = place
            }
        }
    }
}

final class PlaceAnnotation: NSObject, MKAnnotation {
    let place: SavedPlace
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }
    var title: String? { place.title }
    var subtitle: String? { place.category }
    var category: String? { place.category }

    init(place: SavedPlace) { self.place = place }
}
