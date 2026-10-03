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

  func synchronize(_ snapshots: [CertificateSnapshot], store: any SnapshotStore) async throws {
    let center = UNUserNotificationCenter.current()
    let status = await center.notificationSettings().authorizationStatus
    guard status == .authorized || status == .provisional else { return }

    let now = Date()
    let active = snapshots.filter { $0.checkState != .failed && $0.expiresAt != nil }
    let pending = await center.pendingNotificationRequests()
    let validPrefixes = snapshots.compactMap { snapshot -> String? in
      guard let expiry = snapshot.expiresAt else { return nil }
      return "\(prefix)\(snapshot.hostname).\(Int(expiry.timeIntervalSince1970))."
    }
    let obsolete = pending.map(\.identifier).filter { identifier in
      identifier.hasPrefix(prefix) && !validPrefixes.contains(where: identifier.hasPrefix)
    }
    center.removePendingNotificationRequests(withIdentifiers: obsolete)

    let tokens = try store.notificationTokens()
    var added: Set<String> = []
    for snapshot in active {
      guard let expiry = snapshot.expiresAt else { continue }
      let identifierBase = "\(prefix)\(snapshot.hostname).\(Int(expiry.timeIntervalSince1970))."
      for moment in NotificationPolicy.moments(expiresAt: expiry, now: now) {
        let identifier = "\(identifierBase)\(moment.threshold)"
        if let date = moment.date {
          try await center.add(
            makeRequest(
              identifier: identifier, snapshot: snapshot,
              threshold: moment.threshold, date: date))
          added.insert(identifier)
        } else if !tokens.contains(identifier) {
          try await center.add(
            makeRequest(
              identifier: identifier, snapshot: snapshot,
              threshold: moment.threshold, date: nil))
          added.insert(identifier)
        }
      }
    }
    try store.addNotificationTokens(added)
  }

  private func makeRequest(
    identifier: String, snapshot: CertificateSnapshot, threshold: Int, date: Date?
  ) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = threshold == 0 ? "SSL 证书已过期" : "SSL 证书临近到期"
    content.body =
      threshold == 0
      ? "\(snapshot.hostname) 的证书已过期，请尽快处理。"
      : "\(snapshot.hostname) 的证书将在 \(threshold) 天内到期。"
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
