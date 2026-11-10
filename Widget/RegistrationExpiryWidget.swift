import SwiftUI
import WidgetKit

struct RegistrationEntry: TimelineEntry, Sendable {
  let date: Date
  let domains: [RegisteredDomain]
  let snapshots: [RegistrationSnapshot]
  let error: String?
}

struct RegistrationProvider: TimelineProvider {
  func placeholder(in context: Context) -> RegistrationEntry {
    let date = Date()
    return RegistrationEntry(
      date: date, domains: [RegisteredDomain(hostname: "example.com", addedAt: date)],
      snapshots: [
        RegistrationSnapshot(
          hostname: "example.com", checkedAt: date,
          dates: RegistrationDates(registrar: date.addingTimeInterval(18 * 86_400)),
          checkState: .available)
      ],
      error: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (RegistrationEntry) -> Void) {
    completion(context.isPreview ? placeholder(in: context) : cached(at: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<RegistrationEntry>) -> Void)
  {
    let now = Date()
    let stored = cached(at: now)
    let entries = (0...24).map { hour in
      RegistrationEntry(
        date: now.addingTimeInterval(TimeInterval(hour * 3_600)), domains: stored.domains,
        snapshots: stored.snapshots, error: stored.error)
    }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3_600))))
  }

  private func cached(at date: Date) -> RegistrationEntry {
    do {
      let store = try FileSnapshotStore(createIfNeeded: false)
      return RegistrationEntry(
        date: date, domains: try store.registeredDomains(),
        snapshots: try store.registrationSnapshots(), error: nil)
    } catch {
      return RegistrationEntry(
        date: date, domains: [], snapshots: [], error: error.localizedDescription)
    }
  }
}

struct RegistrationExpiryWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: RegistrationWidgetIdentity.kind, provider: RegistrationProvider()) {
      RegistrationWidgetView(entry: $0)
    }
    .configurationDisplayName("域名注册到期")
    .description("显示宿主最近查询的注册日期；登记日期不一定等于续费期限。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct RegistrationWidgetView: View {
  let entry: RegistrationEntry
  var previewFamily: WidgetFamily?
  @Environment(\.widgetFamily) private var systemFamily
  private var family: WidgetFamily { previewFamily ?? systemFamily }

  private var ordered: [RegisteredDomain] {
    entry.domains.sorted {
      let left = snapshot($0.id)?.dates.preferred ?? .distantPast
      let right = snapshot($1.id)?.dates.preferred ?? .distantPast
      return left == right ? $0.id < $1.id : left < right
    }
  }

  var body: some View {
    if previewFamily != nil {
      content
    } else {
      content.containerBackground(.fill.tertiary, for: .widget)
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("域名注册到期", systemImage: "globe").font(.caption.bold())
      if let error = entry.error {
        Text("数据不可用").font(.headline)
        Text(error).font(.caption2).lineLimit(3)
      } else if ordered.isEmpty {
        Text("尚无注册域名").font(.headline)
        Text("打开 App 添加注册域名").font(.caption)
      } else {
        ForEach(Array(ordered.prefix(family == .systemSmall ? 1 : 2))) { domain in
          if family == .systemSmall {
            domainRow(domain)
          } else {
            compactRow(domain)
          }
        }
        if ordered.count > (family == .systemSmall ? 1 : 2) {
          Text("另有 \(ordered.count - (family == .systemSmall ? 1 : 2)) 个域名")
            .font(.caption2).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      Text("App 运行时自动查询")
        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private func domainRow(_ domain: RegisteredDomain) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(domain.hostname).font(.headline).lineLimit(2)
      if let value = snapshot(domain.id) {
        Text(value.label(at: entry.date)).font(.caption2)
          .foregroundStyle(value.needsAttention(at: entry.date) ? Color.orange : Color.primary)
        if let expiry = value.dates.preferred, let days = value.daysRemaining(at: entry.date) {
          Text("\(days) 天 · \(expiry.formatted(date: .numeric, time: .omitted))")
            .font(family == .systemSmall ? .subheadline : .caption).monospacedDigit()
          Text("\(value.checkState == .failed ? "上次已知" : "")\(value.dates.basis)")
            .font(.caption2).foregroundStyle(.secondary)
        }
        if entry.date.timeIntervalSince(value.lastSuccessfulCheckAt ?? .distantPast) > 48 * 3_600 {
          Text("日期数据较旧或尚未获取").font(.caption2).foregroundStyle(.orange)
        }
      } else {
        Text("待检查").font(.caption)
      }
    }
  }

  private func snapshot(_ id: String) -> RegistrationSnapshot? {
    entry.snapshots.first { $0.id == id }
  }

  private func compactRow(_ domain: RegisteredDomain) -> some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(domain.hostname).font(.caption.bold()).lineLimit(1)
        if let value = snapshot(domain.id) {
          let origin =
            value.dates.registrar != nil ? "注册商" : (value.dates.registry != nil ? "注册局" : "参考")
          let stale =
            value.checkState == .failed
            || entry.date.timeIntervalSince(value.lastSuccessfulCheckAt ?? .distantPast) > 48
              * 3_600
          Text("\(value.label(at: entry.date)) · \(stale ? "旧" : "")\(origin)")
            .font(.caption2).lineLimit(1)
            .foregroundStyle(value.needsAttention(at: entry.date) ? Color.orange : Color.secondary)
        } else {
          Text("待检查").font(.caption2).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
      if let value = snapshot(domain.id), let expiry = value.dates.preferred,
        let days = value.daysRemaining(at: entry.date)
      {
        VStack(alignment: .trailing, spacing: 3) {
          Text("\(days) 天").font(.caption.bold()).monospacedDigit()
          Text(expiry.formatted(date: .numeric, time: .omitted)).font(.caption2)
        }
        .foregroundStyle(value.checkState == .failed ? Color.secondary : Color.primary)
      }
    }
  }
}
