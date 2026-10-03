import Foundation

struct DashboardRefresher: Sendable {
  private let checker = CertificateChecker()
  private let maximumConcurrentChecks = 6

  func refresh(_ domains: [WatchedDomain], store: any SnapshotStore) async throws
    -> [CertificateSnapshot]
  {
    var checked: [CertificateSnapshot] = []
    var latest = try store.snapshots()
    try await withThrowingTaskGroup(of: CertificateSnapshot.self) { group in
      var remaining = domains.makeIterator()
      for _ in 0..<min(maximumConcurrentChecks, domains.count) {
        guard let domain = remaining.next() else { break }
        group.addTask { await checker.check(domain) }
      }
      while let result = try await group.next() {
        checked.append(result)
        if checked.count >= maximumConcurrentChecks {
          // 每批落盘，避免较长队列在中途退出时丢失全部已完成结果。
          latest = try store.mergeSnapshots(checked)
          checked.removeAll(keepingCapacity: true)
        }
        if let domain = remaining.next() {
          group.addTask { await checker.check(domain) }
        }
      }
    }
    if !checked.isEmpty {
      latest = try store.mergeSnapshots(checked)
    }
    return latest
  }
}
