import Foundation

struct NotificationMoment: Sendable {
  let threshold: Int
  let date: Date?
}

enum NotificationSchedulingAction: Equatable, Sendable {
  case future(Date)
  case immediate
  case skip
}

enum NotificationPolicy {
  static func validRequestIdentifiers(
    snapshots: [CertificateSnapshot], preferences: ReminderPreferences, prefix: String
  ) -> Set<String> {
    Set(
      snapshots.flatMap { snapshot -> [String] in
        guard let expiry = snapshot.expiresAt else { return [] }
        let base = "\(prefix)\(snapshot.id).\(Int(expiry.timeIntervalSince1970))."
        return (preferences.days + [0]).map { "\(base)\($0)" }
      })
  }

  static func schedulingAction(
    for moment: NotificationMoment, alreadyPending: Bool, tokenRecorded: Bool
  ) -> NotificationSchedulingAction {
    if let date = moment.date { return alreadyPending ? .skip : .future(date) }
    return alreadyPending || tokenRecorded ? .skip : .immediate
  }

  static func moments(
    expiresAt: Date, now: Date, preferences: ReminderPreferences = .standard
  ) -> [NotificationMoment] {
    if expiresAt <= now { return [NotificationMoment(threshold: 0, date: nil)] }
    let available = preferences.thresholds.filter { threshold in
      let date = expiresAt.addingTimeInterval(TimeInterval(-threshold.days * 86_400))
      guard let activatedAt = threshold.activatedAt else { return true }
      return date > now || activatedAt <= date
    }.sorted { $0.days > $1.days }
    let reached = available.reversed().first { threshold in
      expiresAt.addingTimeInterval(TimeInterval(-threshold.days * 86_400)) <= now
    }
    return available.compactMap { threshold in
      let date = expiresAt.addingTimeInterval(TimeInterval(-threshold.days * 86_400))
      if date > now { return NotificationMoment(threshold: threshold.days, date: date) }
      if threshold == reached { return NotificationMoment(threshold: threshold.days, date: nil) }
      return nil
    }
  }
}
