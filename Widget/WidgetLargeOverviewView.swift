import SwiftUI

struct WidgetLargeOverviewView: View {
  let entry: SSLExpiryEntry
  let ordered: [WatchedDomain]

  private var snapshotByID: [String: CertificateSnapshot] {
    Dictionary(uniqueKeysWithValues: entry.snapshots.map { ($0.id, $0) })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      if let focus = ordered.first {
        focusRow(focus)
        Divider()
        VStack(alignment: .leading, spacing: 7) {
          Text("其他端点")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
          ForEach(Array(ordered.dropFirst().prefix(WidgetOverview.visibleLimit - 1))) { domain in
            WidgetLargeEndpointRow(
              domain: domain, snapshot: snapshotByID[domain.id], date: entry.date
            )
            .padding(.vertical, 3)
          }
        }
      }
      if ordered.count <= 3 {
        statusSummary
      }
      Spacer(minLength: 0)
      footer
    }
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Label("证书总览", systemImage: "lock.shield")
        .font(.headline)
      Spacer(minLength: 4)
      Text("\(entry.domains.count) 个监控 · \(attentionCount) 需处理")
        .font(.caption.weight(.medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel("监控 \(entry.domains.count) 个端点，其中 \(attentionCount) 个需处理")
    }
  }

  private var attentionCount: Int {
    WidgetOverview.attentionCount(
      domains: entry.domains, snapshots: entry.snapshots, at: entry.date)
  }

  private var statusSummary: some View {
    let counts = WidgetOverview.severityCounts(
      domains: entry.domains, snapshots: entry.snapshots, at: entry.date)
    let abnormal =
      counts[.expired, default: 0] + counts[.checkFailed, default: 0]
      + counts[.untrusted, default: 0]
    let expiring =
      counts[.critical, default: 0] + counts[.soon, default: 0]
      + counts[.watch, default: 0]
    return VStack(spacing: 8) {
      Divider()
      HStack(spacing: 4) {
        metric("异常", value: abnormal, tint: .red)
        metric("临近", value: expiring, tint: .orange)
        metric("正常", value: counts[.healthy, default: 0], tint: .green)
        metric("待检查", value: counts[.unchecked, default: 0], tint: .secondary)
      }
    }
  }

  private func metric(_ title: String, value: Int, tint: Color) -> some View {
    VStack(spacing: 1) {
      Text("\(value)")
        .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
        .foregroundStyle(value > 0 ? tint : .secondary)
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) \(value) 个")
  }

  private func focusRow(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByID[domain.id]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return HStack(alignment: .center, spacing: 12) {
      CertificateValidityGauge(snapshot: snapshot, date: entry.date, size: 78)
      VStack(alignment: .leading, spacing: 4) {
        Text(domain.displayName)
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
          .truncationMode(.middle)
        Label(severity.label, systemImage: severity.symbol)
          .font(.caption.weight(.medium))
          .foregroundStyle(severity.tint)
        if let snapshot, let expiry = snapshot.expiresAt {
          Text(
            "\(snapshot.checkState == .failed ? "上次已知到期" : "到期") \(expiry.formatted(.dateTime.year().month(.abbreviated).day()))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        }
        if let snapshot {
          Text(checkLabel(snapshot))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private func checkLabel(_ snapshot: CertificateSnapshot) -> String {
    if snapshot.checkState == .failed {
      let lastSuccess =
        snapshot.lastSuccessfulCheckAt.map {
          $0.formatted(date: .abbreviated, time: .omitted)
        } ?? "尚无"
      return "连续失败 \(snapshot.consecutiveFailureCount) 次 · 最近成功 \(lastSuccess)"
    }
    return "检查 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))"
  }

  private var footer: some View {
    HStack(spacing: 5) {
      let hidden = WidgetOverview.hiddenCount(total: ordered.count)
      Text(hidden > 0 ? "另有 \(hidden) 个端点" : "按风险排序")
      Spacer(minLength: 4)
      if entry.errorMessage != nil || entry.reminderErrorMessage != nil {
        WidgetFreshnessFooter(entry: entry, snapshot: nil)
      } else if let lastChecked = entry.snapshots.map(\.checkedAt).max() {
        Text("最近检查 \(lastChecked.formatted(date: .abbreviated, time: .shortened))")
      }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .minimumScaleFactor(0.8)
  }
}

private struct WidgetLargeEndpointRow: View {
  let domain: WatchedDomain
  let snapshot: CertificateSnapshot?
  let date: Date

  var body: some View {
    let severity = snapshot?.severity(at: date) ?? .unchecked
    HStack(alignment: .center, spacing: 7) {
      Image(systemName: severity.symbol)
        .font(.caption)
        .foregroundStyle(severity.tint)
        .frame(width: 16)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(domain.displayName)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.middle)
        if let snapshot, let expiry = snapshot.expiresAt {
          Text(
            "\(snapshot.checkState == .failed ? "已知到期" : "到期") \(expiry.formatted(.dateTime.year().month(.abbreviated).day()))"
          )
          .font(.caption2)
          .foregroundStyle(.secondary)
        } else {
          Text("等待首次检查")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      Text(statusText(severity: severity))
        .font(.caption.weight(.medium).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .accessibilityElement(children: .combine)
  }

  private func statusText(severity: CertificateSeverity) -> String {
    if let snapshot, snapshot.checkState == .trusted,
      let days = snapshot.daysRemaining(at: date)
    {
      return days <= 0 ? "已过期" : "\(days) 天"
    }
    if let snapshot, snapshot.checkState == .failed {
      return "失败 \(snapshot.consecutiveFailureCount) 次"
    }
    return severity.label
  }
}
