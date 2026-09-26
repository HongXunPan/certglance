import SwiftUI
import WidgetKit

struct SSLExpiryWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SSLExpiryEntry

  private var ordered: [WatchedDomain] {
    DashboardOrder.sorted(entry.domains, snapshots: entry.snapshots, at: entry.date)
  }

  private var snapshotByHost: [String: CertificateSnapshot] {
    Dictionary(uniqueKeysWithValues: entry.snapshots.map { ($0.hostname, $0) })
  }

  var body: some View {
    Group {
      if let error = entry.errorMessage, entry.domains.isEmpty {
        stateView(title: "无法读取看板", detail: error, symbol: "exclamationmark.shield")
      } else if ordered.isEmpty {
        stateView(title: "添加域名", detail: "打开 App 开始监控证书", symbol: "plus.circle")
      } else if let focus = ordered.first {
        if family == .systemMedium { mediumContent(focus) } else { smallContent(focus) }
      }
    }
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
  }

  private func smallContent(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByHost[domain.hostname]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return VStack(alignment: .leading, spacing: 0) {
      header
      Spacer(minLength: 5)
      focusMetric(snapshot, severity: severity)
      Text(domain.hostname)
        .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
        .padding(.top, 6)
      footer(snapshot, severity: severity)
        .padding(.top, 5)
    }
    .accessibilityElement(children: .combine)
  }

  private func mediumContent(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByHost[domain.hostname]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return VStack(alignment: .leading, spacing: 10) {
      header
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 0) {
          focusMetric(snapshot, severity: severity)
          Text(domain.hostname)
            .font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            .padding(.top, 4)
          footer(snapshot, severity: severity).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if ordered.count > 1 {
          VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(ordered.dropFirst().prefix(2))) { other in
              compactRow(other)
            }
            Spacer(minLength: 0)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var header: some View {
    HStack {
      Label("SSL 证书", systemImage: "lock.shield")
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Spacer()
      if entry.errorMessage != nil {
        HStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.red)
            .accessibilityHidden(true)
          Text("更新失败")
            .foregroundStyle(.primary)
        }
        .font(.caption2.weight(.semibold))
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开应用查看并主动重试")
      } else {
        Text("\(entry.domains.count)")
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel("监控 \(entry.domains.count) 个域名")
      }
    }
  }

  private func focusMetric(_ snapshot: CertificateSnapshot?, severity: CertificateSeverity)
    -> some View
  {
    HStack(alignment: .firstTextBaseline, spacing: 4) {
      if let snapshot, snapshot.checkState != .failed,
        let days = snapshot.daysRemaining(at: entry.date)
      {
        Text("\(max(0, days))")
          .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
          .contentTransition(.numericText())
          .accessibilityLabel(
            severity == .expired ? "证书已过期" : "证书剩余 \(max(0, days)) 天")
        Text("天")
          .font(.title3.weight(.medium))
          .accessibilityHidden(true)
      } else {
        Image(systemName: severity.symbol)
          .font(.system(size: 38, weight: .semibold))
          .accessibilityHidden(true)
      }
    }
    .foregroundStyle(severity.tint)
    .minimumScaleFactor(0.7)
  }

  private func footer(_ snapshot: CertificateSnapshot?, severity: CertificateSeverity) -> some View
  {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: severity.symbol)
          .foregroundStyle(severity.tint)
          .accessibilityHidden(true)
        Text(severity.label)
          .foregroundStyle(.primary)
      }
      .font(.caption2.weight(.medium))
      if let snapshot, snapshot.checkState != .failed {
        HStack(spacing: 0) {
          Text("上次检查：")
          Text(.currentDate, format: .reference(to: snapshot.checkedAt))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
    }
  }

  private func compactRow(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByHost[domain.hostname]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return HStack(spacing: 7) {
      Image(systemName: severity.symbol)
        .foregroundStyle(severity.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 2) {
        Text(domain.hostname).font(.caption.weight(.medium)).lineLimit(1)
        Text(severity.label).font(.caption2).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      if let days = snapshot?.daysRemaining(at: entry.date), snapshot?.checkState != .failed {
        Text("\(max(0, days))天")
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(.primary)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func stateView(title: String, detail: String, symbol: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Image(systemName: symbol)
        .font(.title2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Spacer()
      Text(title).font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
    }
  }
}
