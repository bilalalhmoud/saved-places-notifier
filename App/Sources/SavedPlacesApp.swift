import SwiftUI
import SwiftData
import UserNotifications
import UIKit

@main
struct SavedPlacesApp: App {
    @StateObject private var model = AppModel()
    private let container: ModelContainer
    private let notificationDelegate = NotificationDelegate()

    init() {
        do {
            container = try ModelContainer(for: SavedPlace.self)
        } catch {
            fatalError("Failed to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    model.configure(with: container.mainContext)
                    notificationDelegate.model = model
                    UNUserNotificationCenter.current().delegate = notificationDelegate
                    model.start()
                }
        }
        .modelContainer(container)
    }
}

/// Handles taps and actions on delivered notifications.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var model: AppModel?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        guard let idString = info["placeID"] as? String,
              let id = UUID(uuidString: idString) else {
            // Batch notification tapped — just surface the app.
            await MainActor.run { model?.selectedPlaceID = nil }
            return
        }

        await MainActor.run {
            guard let model, let place = model.place(for: id) else { return }
            switch NotificationManager.Action(rawValue: response.actionIdentifier) {
            case .navigate:
                if let url = place.navigationURL { UIApplication.shared.open(url) }
            case .openInGoogleMaps:
                if let url = place.googleMapsURL { UIApplication.shared.open(url) }
            case .markVisited:
                model.markVisited(place)
            case .snooze:
                break // dedup state already prevents immediate repeats
            case .none:
                model.selectedPlaceID = id // default tap → open in app
            }
        }
    }
}
