import Foundation

enum WidgetPlanning {
  static let staleInterval: TimeInterval = 12 * 3_600
  static let catchUpInterval: TimeInterval = 3_600
  static let maximumChecksPerTimeline = 6

  static func domainsNeedingCheck(
    _ domains: [WatchedDomain], snapshots: [CertificateSnapshot], at now: Date
  ) -> [WatchedDomain] {
    let byHost = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.hostname, $0) })
    return domains.filter { domain in
      guard let snapshot = byHost[domain.hostname] else { return true }
      return now.timeIntervalSince(snapshot.checkedAt) >= staleInterval
    }
    .sorted { left, right in
      let leftDate = byHost[left.hostname]?.checkedAt ?? .distantPast
      let rightDate = byHost[right.hostname]?.checkedAt ?? .distantPast
      if leftDate != rightDate { return leftDate < rightDate }
      return left.hostname < right.hostname
    }
  }

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
