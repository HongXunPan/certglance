import Foundation

struct ReminderThreshold: Codable, Equatable, Sendable {
  let days: Int
  let activatedAt: Date?
}

struct ReminderPreferences: Equatable, Sendable {
  static let maximumDays = 3_650
  static let standard = ReminderPreferences(
    thresholds: [30, 7, 1].map { ReminderThreshold(days: $0, activatedAt: nil) })

  let thresholds: [ReminderThreshold]

  var days: [Int] { thresholds.map(\.days).sorted(by: >) }

  var isValid: Bool {
    thresholds.allSatisfy { (1...Self.maximumDays).contains($0.days) }
      && Set(thresholds.map(\.days)).count == thresholds.count
  }

  func adding(_ day: Int, at date: Date) throws -> ReminderPreferences {
    guard (1...Self.maximumDays).contains(day) else {
      throw ReminderPreferencesError.invalidDays
    }
    guard !days.contains(day) else { throw ReminderPreferencesError.duplicate }
    return ReminderPreferences(
      thresholds: (thresholds + [ReminderThreshold(days: day, activatedAt: date)])
        .sorted { $0.days > $1.days })
  }

  func removing(_ day: Int) -> ReminderPreferences {
    ReminderPreferences(thresholds: thresholds.filter { $0.days != day })
  }
}

enum ReminderPreferencesError: LocalizedError {
  case invalidDays
  case duplicate

  var errorDescription: String? {
    switch self {
    case .invalidDays: return "请输入 1 至 3650 的整数天数。"
    case .duplicate: return "这个提醒天数已经存在。"
    }
  }
}
