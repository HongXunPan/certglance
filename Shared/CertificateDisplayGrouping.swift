import Foundation

struct CertificateDisplayItem: Identifiable, Sendable {
  var domains: [WatchedDomain]
  let expiryDay: Date?
  let severity: CertificateSeverity

  var id: String { domains[0].id }
  var isGroup: Bool { domains.count > 1 }
  var primary: WatchedDomain { domains[0] }

  func minimumDays(at date: Date, snapshots: [String: CertificateSnapshot]) -> Int? {
    domains.compactMap { snapshots[$0.id]?.daysRemaining(at: date) }.min()
  }
}

enum CertificateDisplayGrouping {
  static func items(
    _ domains: [WatchedDomain], snapshots: [CertificateSnapshot], at date: Date,
    calendar: Calendar = .current
  ) -> [CertificateDisplayItem] {
    let indexed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    let ordered = DashboardOrder.sorted(domains, snapshots: snapshots, at: date)
    var result: [CertificateDisplayItem] = []
    for domain in ordered {
      let snapshot = indexed[domain.id]
      let severity = snapshot?.severity(at: date) ?? .unchecked
      let expiryDay = snapshot.flatMap { snapshot -> Date? in
        guard snapshot.checkState == .trusted, let expiry = snapshot.expiresAt else {
          return nil
        }
        return calendar.startOfDay(for: expiry)
      }
      if let expiryDay, let last = result.indices.last,
        result[last].expiryDay == expiryDay, result[last].severity == severity
      {
        result[last].domains.append(domain)
      } else {
        result.append(
          CertificateDisplayItem(
            domains: [domain], expiryDay: expiryDay, severity: severity))
      }
    }
    return result
  }
}
