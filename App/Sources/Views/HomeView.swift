import SwiftUI
import CoreLocation
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var importing = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.placeCount == 0 {
                    emptyState
                } else {
                    nearbyList
                }
            }
            .navigationTitle("Nearby")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                        .accessibilityLabel("Import places")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText, .item], allowsMultipleSelection: true) { result in
                handleImport(result)
            }
            .alert("Import", isPresented: .constant(importMessage != nil)) {
                Button("OK") { importMessage = nil }
            } message: { Text(importMessage ?? "") }
        }
    }

    private var nearbyList: some View {
        List {
            Section {
                locationStatusRow
            }
            if model.nearby.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Nothing nearby",
                        systemImage: "location.slash",
                        description: Text("No saved places within your notification radius right now.")
                    )
                }
            } else {
                Section("Within range") {
                    ForEach(model.nearby, id: \.place.id) { result in
                        if let place = model.place(for: result.place.id) {
                            NavigationLink { PlaceDetailView(place: place) } label: {
                                NearbyRow(place: place, distance: result.distanceMeters)
                            }
                        }
                    }
                }
            }
        }
        .refreshable { model.refreshNearby() }
    }

    private var locationStatusRow: some View {
        let status = model.locationManager.authorizationStatus
        return HStack {
            Image(systemName: status == .authorizedAlways ? "location.fill" : "location.slash.fill")
                .foregroundStyle(status == .authorizedAlways ? .green : .orange)
            VStack(alignment: .leading) {
                Text(status == .authorizedAlways ? "Monitoring in background" : "Location access needed")
                    .font(.subheadline).bold()
                Text("\(model.placeCount) saved places indexed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if status != .authorizedAlways {
                Button("Enable") { model.locationManager.requestAuthorization() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No saved places yet", systemImage: "mappin.slash")
        } description: {
            Text("Import your Google Maps saved places from a Google Takeout export (.json / .geojson / .csv).")
        } actions: {
            Button("Import from Takeout") { importing = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var total = 0
            for url in urls {
                do { total += try model.importPlaces(from: url) }
                catch { importMessage = error.localizedDescription; return }
            }
            importMessage = "Imported \(total) place\(total == 1 ? "" : "s")."
        case .failure(let error):
            importMessage = error.localizedDescription
        }
    }
}

struct NearbyRow: View {
    let place: SavedPlace
    let distance: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: (place.category ?? "").categorySymbol)
                .foregroundStyle((place.category ?? "Saved").categoryColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.title).font(.body)
                if let category = place.category {
                    Text(category).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(Format.distance(distance))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
