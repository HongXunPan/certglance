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
        group.addTask { await checker.check(domain.hostname) }
      }
      while let result = await group.next() {
        checked.append(result)
        if let domain = remaining.next() {
          group.addTask { await checker.check(domain.hostname) }
        }
      }
    }

    let currentHosts = Set(try store.domains().map(\.hostname))
    var byHost = Dictionary(uniqueKeysWithValues: try store.snapshots().map { ($0.hostname, $0) })
    for result in checked where currentHosts.contains(result.hostname) {
      let old = byHost[result.hostname]
      if let old, result.checkedAt < old.checkedAt { continue }
      if result.checkState == .failed, result.expiresAt == nil, let expiry = old?.expiresAt {
        byHost[result.hostname] = CertificateSnapshot(
          hostname: result.hostname, checkedAt: result.checkedAt,
          expiresAt: expiry, checkState: .failed, detail: result.detail)
      } else {
        byHost[result.hostname] = result
      }
    }
    let merged = byHost.values.filter { currentHosts.contains($0.hostname) }
      .sorted { $0.hostname < $1.hostname }
    try store.saveSnapshots(merged)
    return merged
  }
}
