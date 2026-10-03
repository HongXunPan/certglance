import Foundation
import WidgetKit

struct SSLExpiryEntry: TimelineEntry, Sendable {
  let date: Date
  let domains: [WatchedDomain]
  let snapshots: [CertificateSnapshot]
  let errorMessage: String?
}

struct SSLExpiryProvider: TimelineProvider {
  func placeholder(in context: Context) -> SSLExpiryEntry {
    SSLExpiryEntry(
      date: .now,
      domains: [WatchedDomain(hostname: "example.com", addedAt: .now)],
      snapshots: [
        CertificateSnapshot(
          hostname: "example.com", checkedAt: .now,
          expiresAt: .now.addingTimeInterval(6 * 86_400),
          checkState: .trusted, detail: nil)
      ],
      errorMessage: nil
    )
  }

  func getSnapshot(in context: Context, completion: @escaping (SSLExpiryEntry) -> Void) {
    completion(cachedEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SSLExpiryEntry>) -> Void) {
    let reply = TimelineReply(completion)
    Task {
      var entry = cachedEntry()
      do {
        let store = try FileSnapshotStore(createIfNeeded: false)
        let domains = try store.domains()
        let snapshots = try store.snapshots()
        let snapshotHosts = Set(snapshots.map(\.hostname))
        let domainHosts = Set(domains.map(\.hostname))
        let stale =
          snapshotHosts != domainHosts
          || snapshots.contains { Date().timeIntervalSince($0.checkedAt) >= 12 * 3_600 }
        if !domains.isEmpty && stale {
          let refreshed = try await DashboardRefresher().refresh(domains, store: store)
          entry = SSLExpiryEntry(
            date: .now, domains: domains, snapshots: refreshed, errorMessage: nil)
          try await NotificationCoordinator().synchronize(refreshed, store: store)
        }
      } catch {
        entry = SSLExpiryEntry(
          date: .now, domains: entry.domains,
          snapshots: entry.snapshots, errorMessage: error.localizedDescription)
      }
      reply.complete(
        Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(12 * 3_600))))
    }
  }

  private func cachedEntry() -> SSLExpiryEntry {
    do {
      let store = try FileSnapshotStore(createIfNeeded: false)
      return SSLExpiryEntry(
        date: .now, domains: try store.domains(),
        snapshots: try store.snapshots(), errorMessage: nil)
    } catch {
      return SSLExpiryEntry(
        date: .now, domains: [], snapshots: [],
        errorMessage: error.localizedDescription)
    }
  }
}

private final class TimelineReply: @unchecked Sendable {
  private let completion: (Timeline<SSLExpiryEntry>) -> Void

  init(_ completion: @escaping (Timeline<SSLExpiryEntry>) -> Void) {
    self.completion = completion
  }

  func complete(_ timeline: Timeline<SSLExpiryEntry>) {
    completion(timeline)
  }
}
