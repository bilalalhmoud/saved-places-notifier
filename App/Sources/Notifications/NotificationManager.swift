import Foundation
import UserNotifications
import SavedPlacesCore

/// Builds and schedules local notifications for nearby saved places, including
/// batching ("You have N saved places nearby") and tap actions.
final class NotificationManager: NSObject {
    static let categoryIdentifier = "SAVED_PLACE_NEARBY"
    static let batchCategoryIdentifier = "SAVED_PLACES_BATCH"

    enum Action: String {
        case openInGoogleMaps = "OPEN_GOOGLE_MAPS"
        case navigate = "NAVIGATE"
        case markVisited = "MARK_VISITED"
        case snooze = "SNOOZE"
    }

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        registerCategories()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    private func registerCategories() {
        let center = UNUserNotificationCenter.current()
        let single = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [
                UNNotificationAction(identifier: Action.navigate.rawValue, title: "Navigate", options: [.foreground]),
                UNNotificationAction(identifier: Action.openInGoogleMaps.rawValue, title: "Open in Google Maps", options: [.foreground]),
                UNNotificationAction(identifier: Action.markVisited.rawValue, title: "Mark as visited", options: []),
                UNNotificationAction(identifier: Action.snooze.rawValue, title: "Snooze", options: [])
            ],
            intentIdentifiers: [],
            options: []
        )
        let batch = UNNotificationCategory(
            identifier: Self.batchCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([single, batch])
    }

    /// Presents notifications for the given events. A single event uses the rich
    /// detail format; multiple events are collapsed into one batch notification.
    func present(events: [ProximityEvent], places: [UUID: SavedPlace]) {
        guard !events.isEmpty else { return }
        let center = UNUserNotificationCenter.current()

        if events.count == 1, let event = events.first, let place = places[event.id] {
            let content = UNMutableNotificationContent()
            content.title = "📍 Saved place nearby"
            content.subtitle = place.title
            content.body = detailBody(for: place, distance: event.distanceMeters)
            content.sound = .default
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = ["placeID": place.id.uuidString]
            center.add(UNNotificationRequest(identifier: place.id.uuidString, content: content, trigger: nil))
        } else {
            let content = UNMutableNotificationContent()
            content.title = "📍 Saved places nearby"
            content.body = "You have \(events.count) saved places nearby. Tap to view."
            content.sound = .default
            content.categoryIdentifier = Self.batchCategoryIdentifier
            content.userInfo = ["placeIDs": events.map { $0.id.uuidString }]
            content.badge = NSNumber(value: events.count)
            center.add(UNNotificationRequest(identifier: "batch-\(UUID().uuidString)", content: content, trigger: nil))
        }
    }

    private func detailBody(for place: SavedPlace, distance: Double) -> String {
        var lines = ["\(Int(distance.rounded())) metres away"]
        if let category = place.category, !category.isEmpty {
            lines.append("Saved in: \(category)")
        }
        return lines.joined(separator: "\n")
    }
}
