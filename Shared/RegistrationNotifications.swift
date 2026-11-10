import Foundation
import UserNotifications

enum RegistrationNotificationPolicy {
  static let prefix = "certglance.registration."

  static func base(for snapshot: RegistrationSnapshot) -> String? {
    guard snapshot.dates.isValid, let expiry = snapshot.dates.preferred else { return nil }
    let basis =
      snapshot.dates.registrar != nil
      ? "registrar" : (snapshot.dates.registry != nil ? "registry" : "reported")
    return "\(prefix)\(snapshot.id).\(basis).\(Int(expiry.timeIntervalSince1970))."
  }

  static func validIdentifiers(
    snapshots: [RegistrationSnapshot], preferences: ReminderPreferences
  ) -> Set<String> {
    Set(
      snapshots.flatMap { snapshot -> [String] in
        guard let base = base(for: snapshot) else { return [] }
        return (preferences.days + [0]).map { "\(base)\($0)" }
      })
  }
}

struct RegistrationNotifications: Sendable {
  func synchronize(store: any RegistrationStore) async throws {
    let center = UNUserNotificationCenter.current()
    let preferences = try store.reminderPreferences()
    let snapshots = try store.registrationSnapshots()
    let pending = await removeObsolete(
      center: center, snapshots: snapshots, preferences: preferences)
    let authorization = await center.notificationSettings().authorizationStatus
    guard authorization == .authorized || authorization == .provisional else { return }
    let tokens = try store.notificationTokens()
    let now = Date()
    for snapshot in snapshots where snapshot.checkState == .available {
      guard let expiry = snapshot.dates.preferred,
        let base = RegistrationNotificationPolicy.base(for: snapshot)
      else { continue }
      for moment in NotificationPolicy.moments(
        expiresAt: expiry, now: now, preferences: preferences)
      {
        try Task.checkCancellation()
        let identifier = "\(base)\(moment.threshold)"
        let action = NotificationPolicy.schedulingAction(
          for: moment, alreadyPending: pending.contains(identifier),
          tokenRecorded: tokens.contains(identifier))
        if case .skip = action {
          if pending.contains(identifier), !tokens.contains(identifier) {
            try store.addNotificationTokens([identifier])
          }
          continue
        }
        let current = try store.registrationSnapshots().contains {
          $0.id == snapshot.id && $0.checkState == .available && $0.dates == snapshot.dates
        }
        guard current else { continue }
        let content = UNMutableNotificationContent()
        content.title = snapshot.dates.needsConfirmation ? "域名登记日期提醒" : "域名注册到期提醒"
        let when = moment.threshold == 0 ? "已到" : "将在 \(moment.threshold) 天内到达"
        content.body =
          "\(snapshot.hostname) 的\(snapshot.dates.basis)\(when)。"
          + (snapshot.dates.needsConfirmation ? "这不代表实际续费期限，请向注册商核对。" : "请核对续费情况。")
        content.sound = .default
        let trigger: UNNotificationTrigger
        switch action {
        case .future(let date):
          let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date)
          trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .immediate:
          trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        case .skip: continue
        }
        try await center.add(
          UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        try store.addNotificationTokens([identifier])
      }
    }
    _ = await removeObsolete(
      center: center, snapshots: try store.registrationSnapshots(),
      preferences: try store.reminderPreferences())
  }

  private func removeObsolete(
    center: UNUserNotificationCenter, snapshots: [RegistrationSnapshot],
    preferences: ReminderPreferences
  ) async -> Set<String> {
    let valid = RegistrationNotificationPolicy.validIdentifiers(
      snapshots: snapshots, preferences: preferences)
    let pending = await center.pendingNotificationRequests().map(\.identifier)
    let obsolete = pending.filter {
      $0.hasPrefix(RegistrationNotificationPolicy.prefix) && !valid.contains($0)
    }
    center.removePendingNotificationRequests(withIdentifiers: obsolete)
    return Set(pending).subtracting(obsolete)
  }
}

extension NotificationCoordinator {
  func synchronizeMonitors(store: any SnapshotStore) async throws {
    try await synchronize(store: store)
    if let registrationStore = store as? any RegistrationStore {
      try await RegistrationNotifications().synchronize(store: registrationStore)
    }
  }
}
