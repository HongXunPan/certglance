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
      var reloadInterval = DomainCheckQueue.minimumCheckInterval
      do {
        let store = try FileSnapshotStore(createIfNeeded: false)
        let domains = try store.domains()
        let snapshots = try store.snapshots()
        let due = DomainCheckQueue.due(domains, snapshots: snapshots, at: .now)
        if !due.isEmpty {
          _ = try await DashboardRefresher().refresh(
            Array(due.prefix(WidgetPlanning.maximumChecksPerTimeline)), store: store)
          try await NotificationCoordinator().synchronize(store: store)
        }
        let currentDomains = try store.domains()
        let currentSnapshots = try store.snapshots()
        entry = SSLExpiryEntry(
          date: .now, domains: currentDomains, snapshots: currentSnapshots, errorMessage: nil)
        if !DomainCheckQueue.due(currentDomains, snapshots: currentSnapshots, at: .now).isEmpty {
          reloadInterval = WidgetPlanning.catchUpInterval
        }
      } catch {
        entry = SSLExpiryEntry(
          date: .now, domains: entry.domains,
          snapshots: entry.snapshots, errorMessage: error.localizedDescription)
      }
      let now = Date()
      let entries = WidgetPlanning.timelineDates(snapshots: entry.snapshots, from: now).map {
        SSLExpiryEntry(
          date: $0, domains: entry.domains,
          snapshots: entry.snapshots, errorMessage: entry.errorMessage)
      }
      reply.complete(
        Timeline(entries: entries, policy: .after(now.addingTimeInterval(reloadInterval))))
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
