import Foundation

struct NotificationMoment: Sendable {
  let threshold: Int
  let date: Date?
}

enum NotificationPolicy {
  static let thresholds = [30, 7, 1]

  static func moments(expiresAt: Date, now: Date) -> [NotificationMoment] {
    if expiresAt <= now { return [NotificationMoment(threshold: 0, date: nil)] }
    let reached = thresholds.reversed().first { threshold in
      expiresAt.addingTimeInterval(TimeInterval(-threshold * 86_400)) <= now
    }
    return thresholds.compactMap { threshold in
      let date = expiresAt.addingTimeInterval(TimeInterval(-threshold * 86_400))
      if date > now { return NotificationMoment(threshold: threshold, date: date) }
      if threshold == reached { return NotificationMoment(threshold: threshold, date: nil) }
      return nil
    }
  }
}
