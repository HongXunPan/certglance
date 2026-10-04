import SwiftUI

struct WidgetLargeOverviewView: View {
  let entry: SSLExpiryEntry
  let ordered: [WatchedDomain]

  private var snapshotByID: [String: CertificateSnapshot] {
    Dictionary(uniqueKeysWithValues: entry.snapshots.map { ($0.id, $0) })
  }

  private var displayItems: [CertificateDisplayItem] {
    CertificateDisplayGrouping.items(
      entry.domains, snapshots: entry.snapshots, at: entry.date)
  }

  private var visibleItems: [CertificateDisplayItem] {
    Array(displayItems.prefix(WidgetOverview.largeVisibleLimit))
  }

  private var hiddenCount: Int {
    WidgetOverview.hiddenCount(
      total: ordered.count, items: displayItems,
      visibleLimit: WidgetOverview.largeVisibleLimit)
  }

  private var attentionCount: Int {
    WidgetOverview.attentionCount(
      domains: entry.domains, snapshots: entry.snapshots, at: entry.date)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      if displayItems.count == 1, let domain = ordered.first {
        Spacer(minLength: 0)
        singleEndpoint(domain)
        Spacer(minLength: 0)
      } else {
        ForEach(visibleItems.indices, id: \.self) { index in
          if index > 0 {
            Divider()
          }
          WidgetRiskRow(
            item: visibleItems[index], snapshots: snapshotByID, date: entry.date, badgeSize: 36)
        }
        Spacer(minLength: 0)
        if hiddenCount == 0 || visibleItems.count < WidgetOverview.largeVisibleLimit {
          statusBand
        }
      }
      if hiddenCount > 0 || entry.errorMessage != nil || entry.reminderErrorMessage != nil {
        footer
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Label("证书到期", systemImage: "lock.shield")
        .font(.headline)
      Spacer(minLength: 4)
      Text("\(attentionCount) 需处理 · 共 \(entry.domains.count) 个")
        .font(.caption.weight(.medium).monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityLabel("监控 \(entry.domains.count) 个端点，其中 \(attentionCount) 个需处理")
    }
  }

  private var footer: some View {
    HStack(spacing: 5) {
      if hiddenCount > 0 {
        Text("另有 \(hiddenCount) 个端点")
      }
      Spacer(minLength: 4)
      if entry.errorMessage != nil || entry.reminderErrorMessage != nil {
        WidgetFreshnessFooter(entry: entry, snapshot: nil)
      }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .lineLimit(1)
  }

  private func singleEndpoint(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByID[domain.id]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return HStack(alignment: .center, spacing: 14) {
      CertificateValidityGauge(snapshot: snapshot, date: entry.date, size: 104)
      VStack(alignment: .leading, spacing: 5) {
        Text(domain.displayName)
          .font(.headline)
          .lineLimit(2)
          .truncationMode(.middle)
        Label(severity.label, systemImage: severity.symbol)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(severity.tint)
        if let snapshot, let expiry = snapshot.expiresAt {
          Text(
            "\(snapshot.checkState == .failed ? "已知到期" : "到期") \(expiry.formatted(.dateTime.year().month().day()))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        if let snapshot {
          Text("检查 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .combine)
  }

  private var statusBand: some View {
    let counts = WidgetOverview.severityCounts(
      domains: entry.domains, snapshots: entry.snapshots, at: entry.date)
    let abnormal =
      counts[.expired, default: 0] + counts[.checkFailed, default: 0]
      + counts[.untrusted, default: 0]
    let nearing =
      counts[.critical, default: 0] + counts[.soon, default: 0]
      + counts[.watch, default: 0]
    return VStack(spacing: 5) {
      Divider()
      HStack(spacing: 0) {
        statusMetric("异常", value: abnormal, tint: .red)
        statusMetric("临近", value: nearing, tint: .orange)
        statusMetric("正常", value: counts[.healthy, default: 0], tint: .green)
        statusMetric("待检查", value: counts[.unchecked, default: 0], tint: .secondary)
      }
    }
  }

  private func statusMetric(_ title: String, value: Int, tint: Color) -> some View {
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
}
