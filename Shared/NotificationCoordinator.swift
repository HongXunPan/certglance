import Foundation
import UserNotifications

struct NotificationCoordinator: Sendable {
  private let prefix = "ssl-widget."

  func authorizationStatus() async -> UNAuthorizationStatus {
    await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
  }

  func requestAuthorization() async throws -> Bool {
    try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
  }

  func synchronize(store: any SnapshotStore) async throws {
    let center = UNUserNotificationCenter.current()
    let snapshots = try store.snapshots()
    let preferences = try store.reminderPreferences()
    let pendingIdentifiers = await removeObsoleteRequests(
      center: center, snapshots: snapshots, preferences: preferences)
    let status = await center.notificationSettings().authorizationStatus
    guard status == .authorized || status == .provisional else { return }

    let now = Date()
    let active = snapshots.filter { $0.checkState != .failed && $0.expiresAt != nil }

    let tokens = try store.notificationTokens()
    var scheduleError: Error?
    do {
      for snapshot in active {
        guard let expiry = snapshot.expiresAt else { continue }
        let identifierBase = "\(prefix)\(snapshot.id).\(Int(expiry.timeIntervalSince1970))."
        for moment in NotificationPolicy.moments(
          expiresAt: expiry, now: now, preferences: preferences)
        {
          let identifier = "\(identifierBase)\(moment.threshold)"
          let action = NotificationPolicy.schedulingAction(
            for: moment,
            alreadyPending: pendingIdentifiers.contains(identifier),
            tokenRecorded: tokens.contains(identifier))
          switch action {
          case .future(let date):
            try await center.add(
              makeRequest(
                identifier: identifier, snapshot: snapshot,
                threshold: moment.threshold, date: date))
            try store.addNotificationTokens([identifier])
          case .immediate:
            let stillCurrent = try store.snapshots().contains {
              $0.id == snapshot.id && $0.expiresAt == expiry
                && $0.checkState != .failed
            }
            if !stillCurrent { continue }
            try await center.add(
              makeRequest(
                identifier: identifier, snapshot: snapshot,
                threshold: moment.threshold, date: nil))
            try store.addNotificationTokens([identifier])
          case .skip:
            if pendingIdentifiers.contains(identifier) && !tokens.contains(identifier) {
              try store.addNotificationTokens([identifier])
            }
          }
        }
      }
    } catch {
      scheduleError = error
    }
    _ = await removeObsoleteRequests(
      center: center, snapshots: try store.snapshots(),
      preferences: try store.reminderPreferences())
    if let scheduleError { throw scheduleError }
  }

  private func removeObsoleteRequests(
    center: UNUserNotificationCenter, snapshots: [CertificateSnapshot],
    preferences: ReminderPreferences
  ) async -> Set<String> {
    let validIdentifiers = NotificationPolicy.validRequestIdentifiers(
      snapshots: snapshots, preferences: preferences, prefix: prefix)
    let pending = await center.pendingNotificationRequests()
    let obsolete = pending.map(\.identifier).filter { identifier in
      identifier.hasPrefix(prefix) && !validIdentifiers.contains(identifier)
    }
    center.removePendingNotificationRequests(withIdentifiers: obsolete)
    return Set(pending.map(\.identifier)).subtracting(obsolete)
  }

  private func makeRequest(
    identifier: String, snapshot: CertificateSnapshot, threshold: Int, date: Date?
  ) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = threshold == 0 ? "SSL 证书已过期" : "SSL 证书临近到期"
    content.body =
      threshold == 0
      ? "\(snapshot.displayName) 的证书已过期，请尽快处理。"
      : "\(snapshot.displayName) 的证书将在 \(threshold) 天内到期。"
    content.sound = .default
    let trigger: UNNotificationTrigger
    if let date {
      let components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: date)
      trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    } else {
      trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
    }
    return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
  }
}
