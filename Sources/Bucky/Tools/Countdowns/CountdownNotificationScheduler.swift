import Foundation
import UserNotifications

@MainActor
final class CountdownNotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var updateGeneration = 0

    override init() {
        super.init()
        center.delegate = self
    }

    func restoreScheduledNotifications(for countdowns: [Countdown]) {
        reconcile(countdowns, requestAuthorization: false)
    }

    func countdownsDidChange(_ countdowns: [Countdown]) {
        reconcile(countdowns, requestAuthorization: true)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    private func reconcile(_ countdowns: [Countdown], requestAuthorization: Bool) {
        updateGeneration += 1
        let generation = updateGeneration

        Task { @MainActor [weak self] in
            guard let self else { return }
            var settings = await center.notificationSettings()

            if requestAuthorization, settings.authorizationStatus == .notDetermined {
                do {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                } catch {
                    return
                }
                settings = await center.notificationSettings()
            }

            guard generation == updateGeneration,
                  settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional else {
                return
            }

            await synchronizePendingRequests(with: countdowns)
        }
    }

    private func synchronizePendingRequests(with countdowns: [Countdown]) async {
        let futureCountdowns = countdowns.filter { $0.targetDate > Date() }
        let existingIdentifiers = Set(countdowns.map(Self.identifier(for:)))
        let desiredIdentifiers = Set(futureCountdowns.map(Self.identifier(for:)))
        let pendingRequests = await center.pendingNotificationRequests()
        let stalePendingIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) && !desiredIdentifiers.contains($0) }
        let deliveredNotifications = await center.deliveredNotifications()
        let deletedCountdownIdentifiers = deliveredNotifications
            .map { $0.request.identifier }
            .filter { $0.hasPrefix(Self.identifierPrefix) && !existingIdentifiers.contains($0) }

        center.removePendingNotificationRequests(withIdentifiers: stalePendingIdentifiers)
        center.removeDeliveredNotifications(withIdentifiers: deletedCountdownIdentifiers)

        for countdown in futureCountdowns {
            let content = UNMutableNotificationContent()
            content.title = "Countdown finished"
            content.body = countdown.name
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.era, .year, .month, .day, .hour, .minute, .second],
                from: countdown.targetDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.identifier(for: countdown),
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                // Keep the countdown intact; the notification center may reject it without affecting stored data.
            }
        }
    }

    private static let identifierPrefix = "bucky.countdown."

    private static func identifier(for countdown: Countdown) -> String {
        identifierPrefix + countdown.id.uuidString
    }
}
