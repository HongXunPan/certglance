import Foundation
import WidgetKit

struct SSLExpiryEntry: TimelineEntry, Sendable {
  let date: Date
  let domains: [WatchedDomain]
  let snapshots: [CertificateSnapshot]
  let errorMessage: String?
  let reminderErrorMessage: String?
  let selection: WidgetDisplaySelection

  init(
    date: Date, domains: [WatchedDomain], snapshots: [CertificateSnapshot],
    errorMessage: String?, reminderErrorMessage: String?,
    selection: WidgetDisplaySelection = .automatic
  ) {
    self.date = date
    self.domains = domains
    self.snapshots = snapshots
    self.errorMessage = errorMessage
    self.reminderErrorMessage = reminderErrorMessage
    self.selection = selection
  }

  func at(_ date: Date) -> SSLExpiryEntry {
    SSLExpiryEntry(
      date: date, domains: domains, snapshots: snapshots,
      errorMessage: errorMessage, reminderErrorMessage: reminderErrorMessage,
      selection: selection)
  }
}

struct SSLExpiryProvider: TimelineProvider {
  func placeholder(in context: Context) -> SSLExpiryEntry {
    WidgetTimelineSource.placeholder(selection: .automatic)
  }

  func getSnapshot(in context: Context, completion: @escaping (SSLExpiryEntry) -> Void) {
    completion(WidgetTimelineSource.cachedEntry(selection: .automatic))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<SSLExpiryEntry>) -> Void) {
    let reply = TimelineReply(completion)
    Task {
      reply.complete(await WidgetTimelineSource.timeline(selection: .automatic))
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
