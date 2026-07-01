import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            SettingsForm(settings: model.settings, model: model)
                .navigationTitle("Settings")
        }
    }
}

private struct SettingsForm: View {
    @ObservedObject var settings: AppSettings
    let model: AppModel

    @State private var importing = false
    @State private var confirmDelete = false
    @State private var importMessage: String?

    var body: some View {
        Form {
            Section("Notification radius") {
                VStack(alignment: .leading) {
                    Text("\(Int(settings.baseRadiusMeters)) metres")
                        .font(.headline.monospacedDigit())
                    Slider(value: $settings.baseRadiusMeters, in: 100...1000, step: 50)
                    Text("Base distance for alerts. Common values: 250, 500, 750, 1000 m.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Adaptive radius by transport", isOn: $settings.adaptiveRadius)
            }

            Section("Frequency & duplicates") {
                Picker("Re-notify", selection: $settings.cooldown) {
                    ForEach(Cooldown.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper("Max \(settings.maxNotificationsPerBatch) per batch", value: $settings.maxNotificationsPerBatch, in: 1...20)
                Stepper("At least \(settings.minMinutesBetweenNotifications) min apart", value: $settings.minMinutesBetweenNotifications, in: 0...120, step: 5)
            }

            Section("When to notify") {
                Picker("Time window", selection: $settings.timeWindow) {
                    ForEach(TimeWindow.allCases) { Text($0.displayName).tag($0) }
                }
                ForEach([TransportMode.walking, .cycling, .driving, .transit], id: \.self) { mode in
                    Toggle(mode.displayName, isOn: Binding(
                        get: { settings.allowedTransportModes.contains(mode) },
                        set: { on in
                            if on { settings.allowedTransportModes.insert(mode) }
                            else { settings.allowedTransportModes.remove(mode) }
                        }
                    ))
                }
            }

            Section("Battery") {
                Picker("Location accuracy", selection: $settings.batteryMode) {
                    ForEach(BatteryMode.allCases) { Text($0.displayName).tag($0) }
                }
                Text("Battery Saver uses only significant-change and visit monitoring. Balanced raises accuracy only when a saved place is near.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !model.categories.isEmpty {
                Section("Categories") {
                    ForEach(model.categories, id: \.self) { category in
                        Toggle(isOn: Binding(
                            get: { !settings.disabledCategories.contains(category) },
                            set: { on in
                                if on { settings.disabledCategories.remove(category) }
                                else { settings.disabledCategories.insert(category) }
                            }
                        )) {
                            Label(category, systemImage: category.categorySymbol)
                        }
                    }
                }
            }

            Section("Maps") {
                Toggle("Prefer Google Maps for directions", isOn: $settings.preferGoogleMaps)
            }

            Section("Data") {
                Button {
                    importing = true
                } label: {
                    Label("Import from Google Takeout", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete all places", systemImage: "trash")
                }
                LabeledContent("Saved places", value: "\(model.placeCount)")
            }

            Section("About") {
                LabeledContent("Privacy", value: "On-device only")
                Text("Everything is stored locally on your iPhone. Your location never leaves your device and no account is required.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .commaSeparatedText, .item], allowsMultipleSelection: true) { result in
            handleImport(result)
        }
        .alert("Delete all places?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { model.deleteAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes every imported place from this device.")
        }
        .alert("Import", isPresented: .constant(importMessage != nil)) {
            Button("OK") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
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
