import Foundation
import WidgetKit

enum WidgetTimelineSource {
  static func placeholder(selection: WidgetDisplaySelection) -> SSLExpiryEntry {
    SSLExpiryEntry(
      date: .now,
      domains: [WatchedDomain(hostname: "example.com", addedAt: .now)],
      snapshots: [
        CertificateSnapshot(
          hostname: "example.com", checkedAt: .now,
          expiresAt: .now.addingTimeInterval(6 * 86_400),
          checkState: .trusted, detail: nil,
          validFrom: .now.addingTimeInterval(-84 * 86_400))
      ],
      errorMessage: nil, reminderErrorMessage: nil, selection: selection)
  }

  static func cachedEntry(selection: WidgetDisplaySelection) -> SSLExpiryEntry {
    do {
      let store = try FileSnapshotStore(createIfNeeded: false)
      return SSLExpiryEntry(
        date: .now, domains: try store.domains(), snapshots: try store.snapshots(),
        errorMessage: nil, reminderErrorMessage: nil, selection: selection)
    } catch {
      return SSLExpiryEntry(
        date: .now, domains: [], snapshots: [],
        errorMessage: error.localizedDescription, reminderErrorMessage: nil,
        selection: selection)
    }
  }

  static func timeline(selection: WidgetDisplaySelection) async -> Timeline<SSLExpiryEntry> {
    var entry = cachedEntry(selection: selection)
    var reloadInterval = DomainCheckQueue.minimumCheckInterval
    do {
      let store = try FileSnapshotStore(createIfNeeded: false)
      let domains = try store.domains()
      let snapshots = try store.snapshots()
      var refreshError: String?
      var reminderError: String?
      if !DomainCheckQueue.due(domains, snapshots: snapshots, at: .now).isEmpty,
        let lease = try store.tryAcquireWidgetRefreshLease()
      {
        defer { withExtendedLifetime(lease) {} }
        let currentDomains = try store.domains()
        let currentSnapshots = try store.snapshots()
        let due = DomainCheckQueue.due(currentDomains, snapshots: currentSnapshots, at: .now)
        if !due.isEmpty,
          try lease.beginBatch(at: .now, minimumSpacing: WidgetPlanning.catchUpInterval)
        {
          do {
            _ = try await DashboardRefresher().refresh(
              Array(due.prefix(WidgetPlanning.maximumChecksPerTimeline)), store: store)
          } catch {
            refreshError = error.localizedDescription
          }
          do {
            try await NotificationCoordinator().synchronize(store: store)
          } catch {
            reminderError = error.localizedDescription
          }
        }
      }
      let latestDomains = try store.domains()
      let latestSnapshots = try store.snapshots()
      entry = SSLExpiryEntry(
        date: .now, domains: latestDomains, snapshots: latestSnapshots,
        errorMessage: refreshError, reminderErrorMessage: reminderError,
        selection: selection)
      if !DomainCheckQueue.due(latestDomains, snapshots: latestSnapshots, at: .now).isEmpty {
        reloadInterval = WidgetPlanning.catchUpInterval
      }
    } catch {
      entry = SSLExpiryEntry(
        date: .now, domains: entry.domains, snapshots: entry.snapshots,
        errorMessage: error.localizedDescription, reminderErrorMessage: nil,
        selection: selection)
    }
    let now = Date()
    let entries = WidgetPlanning.timelineDates(snapshots: entry.snapshots, from: now).map {
      entry.at($0)
    }
    return Timeline(entries: entries, policy: .after(now.addingTimeInterval(reloadInterval)))
  }
}
