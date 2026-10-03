import Foundation

enum WidgetDisplaySelection: Equatable, Sendable {
  case automatic
  case pinned(String?)

  func resolve(in ordered: [WatchedDomain]) -> WatchedDomain? {
    switch self {
    case .automatic:
      return ordered.first
    case .pinned(let id):
      guard let id else { return nil }
      return ordered.first { $0.id == id }
    }
  }
}

enum WidgetOverview {
  static let visibleLimit = 5

  static func severityCounts(
    domains: [WatchedDomain], snapshots: [CertificateSnapshot], at date: Date
  ) -> [CertificateSeverity: Int] {
    let indexed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    var counts: [CertificateSeverity: Int] = [:]
    for domain in domains {
      let severity = indexed[domain.id]?.severity(at: date) ?? .unchecked
      counts[severity, default: 0] += 1
    }
    return counts
  }

  static func attentionCount(
    domains: [WatchedDomain], snapshots: [CertificateSnapshot], at date: Date
  ) -> Int {
    let healthy = severityCounts(
      domains: domains, snapshots: snapshots, at: date)[.healthy, default: 0]
    return domains.count - healthy
  }

  static func hiddenCount(total: Int) -> Int {
    max(0, total - visibleLimit)
  }
}
