import Foundation

enum WidgetPlanning {
  static let catchUpInterval: TimeInterval = 3_600
  static let maximumChecksPerTimeline = 6

  static func timelineDates(
    snapshots: [CertificateSnapshot], from now: Date,
    horizon: TimeInterval = 7 * 86_400, maximumEntries: Int = 96
  ) -> [Date] {
    let end = now.addingTimeInterval(horizon)
    let candidates = snapshots.compactMap(\.expiresAt).flatMap { expiry -> [Date] in
      guard expiry > now else { return [] }
      let remaining = Int(ceil(expiry.timeIntervalSince(now) / 86_400))
      return (1...min(remaining, 7)).map { offset in
        expiry.addingTimeInterval(TimeInterval(-(remaining - offset) * 86_400 + 1))
      }
    }
    .filter { $0 > now && $0 <= end }
    let uniqueCandidates = Set(candidates).sorted()

    var dates = [now]
    for candidate in uniqueCandidates {
      let scheduled = max(candidate, dates[dates.count - 1].addingTimeInterval(300))
      if scheduled > end || dates.count >= maximumEntries { break }
      dates.append(scheduled)
    }
    return dates
  }
}
