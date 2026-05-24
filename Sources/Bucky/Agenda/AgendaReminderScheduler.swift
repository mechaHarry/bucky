import Foundation
import UserNotifications

protocol AgendaReminderScheduling {
    func sync(reminders: [AgendaReminder])
    func schedule(_ reminder: AgendaReminder)
    func cancelReminder(id: UUID)
}

struct NoOpAgendaReminderScheduler: AgendaReminderScheduling {
    func sync(reminders: [AgendaReminder]) {}
    func schedule(_ reminder: AgendaReminder) {}
    func cancelReminder(id: UUID) {}
}

final class UserNotificationAgendaReminderScheduler: NSObject, AgendaReminderScheduling {
    private let center: UNUserNotificationCenter
    private let identifierPrefix = "bucky.agenda.reminder."

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func sync(reminders: [AgendaReminder]) {
        center.getPendingNotificationRequests { [self, identifierPrefix, center] requests in
            let identifiers = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(identifierPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            reminders.forEach { reminder in
                self.schedule(reminder)
            }
        }
    }

    func schedule(_ reminder: AgendaReminder) {
        guard let dateComponents = reminder.notificationDateComponents else { return }
        requestAuthorizationIfNeeded { [center, identifierPrefix] granted in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = reminder.name.isEmpty ? "Agenda Reminder" : reminder.name
            content.body = reminder.details.isEmpty ? reminder.urlString : reminder.details
            content.sound = .default
            if !reminder.urlString.isEmpty {
                content.userInfo = ["url": reminder.urlString]
            }

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + reminder.id.uuidString,
                content: content,
                trigger: trigger
            )
            center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            center.add(request) { error in
                if let error {
                    NSLog("Bucky could not schedule agenda reminder %@: %@", reminder.id.uuidString, error.localizedDescription)
                }
            }
        }
    }

    func cancelReminder(id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [identifierPrefix + id.uuidString])
    }

    private func requestAuthorizationIfNeeded(_ completion: @escaping (Bool) -> Void) {
        center.getNotificationSettings { [center] settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                completion(true)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        NSLog("Bucky could not request notification permission: %@", error.localizedDescription)
                    }
                    completion(granted)
                }
            case .denied:
                completion(false)
            @unknown default:
                completion(false)
            }
        }
    }
}

extension UserNotificationAgendaReminderScheduler: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
