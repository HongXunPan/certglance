import Foundation

enum DomainCheckQueue {
  static let minimumCheckInterval: TimeInterval = 12 * 3_600
  static let overdueInterval: TimeInterval = 24 * 3_600

  static func due(
    _ domains: [WatchedDomain], snapshots: [CertificateSnapshot], at now: Date
  ) -> [WatchedDomain] {
    let byHost = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.hostname, $0) })
    return ordered(
      domains.filter { domain in
        guard let snapshot = byHost[domain.hostname] else { return true }
        return now.timeIntervalSince(snapshot.checkedAt) >= minimumCheckInterval
      },
      snapshots: snapshots, at: now)
  }

  static func ordered(
    _ domains: [WatchedDomain], snapshots: [CertificateSnapshot], at now: Date
  ) -> [WatchedDomain] {
    let byHost = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.hostname, $0) })
    return domains.sorted { left, right in
      let leftSnapshot = byHost[left.hostname]
      let rightSnapshot = byHost[right.hostname]
      let leftTier = tier(for: leftSnapshot, at: now)
      let rightTier = tier(for: rightSnapshot, at: now)
      if leftTier != rightTier { return leftTier > rightTier }

      let leftScore = score(for: leftSnapshot, at: now)
      let rightScore = score(for: rightSnapshot, at: now)
      if leftScore != rightScore { return leftScore > rightScore }

      let leftDate = leftSnapshot?.checkedAt ?? left.addedAt
      let rightDate = rightSnapshot?.checkedAt ?? right.addedAt
      if leftDate != rightDate { return leftDate < rightDate }
      return left.hostname < right.hostname
    }
  }

  private static func tier(for snapshot: CertificateSnapshot?, at now: Date) -> Int {
    guard let snapshot else { return 2 }
    return now.timeIntervalSince(snapshot.checkedAt) >= overdueInterval ? 1 : 0
  }

  private static func score(for snapshot: CertificateSnapshot?, at now: Date) -> Int {
    guard let snapshot else { return 0 }
    var points = 0
    if let expiry = snapshot.expiresAt {
      let remaining = expiry.timeIntervalSince(now)
      if remaining <= 0 {
        points += 60
      } else if remaining <= 86_400 {
        points += 45
      } else if remaining <= 7 * 86_400 {
        points += 30
      } else if remaining <= 30 * 86_400 {
        points += 15
      }
    }
    if snapshot.checkState == .untrusted { points += 20 }
    switch snapshot.consecutiveFailureCount {
    case 1: points += 10
    case 2...: points += 18
    default: break
    }
    if let lastSuccess = snapshot.lastSuccessfulCheckAt {
      let age = now.timeIntervalSince(lastSuccess)
      if age >= 7 * 86_400 {
        points += 18
      } else if age >= 3 * 86_400 {
        points += 12
      } else if age >= 86_400 {
        points += 6
      }
    } else {
      points += 18
    }
    return points
  }
}
