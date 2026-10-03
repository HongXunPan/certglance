import Foundation

struct DashboardRefresher: Sendable {
  private let checker = CertificateChecker()
  private let maximumConcurrentChecks = 6

  func refresh(_ domains: [WatchedDomain], store: any SnapshotStore) async throws
    -> [CertificateSnapshot]
  {
    var checked: [CertificateSnapshot] = []
    await withTaskGroup(of: CertificateSnapshot.self) { group in
      var remaining = domains.makeIterator()
      for _ in 0..<min(maximumConcurrentChecks, domains.count) {
        guard let domain = remaining.next() else { break }
        group.addTask { await checker.check(domain) }
      }
      while let result = await group.next() {
        checked.append(result)
        if let domain = remaining.next() {
          group.addTask { await checker.check(domain) }
        }
      }
    }

    return try store.mergeSnapshots(checked)
  }
}
