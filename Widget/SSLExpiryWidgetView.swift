import SwiftUI
import WidgetKit

struct SSLExpiryWidgetView: View {
  @Environment(\.widgetFamily) private var family
  let entry: SSLExpiryEntry
  var previewFamily: WidgetFamily?

  private var effectiveFamily: WidgetFamily { previewFamily ?? family }

  private var ordered: [WatchedDomain] {
    DashboardOrder.sorted(entry.domains, snapshots: entry.snapshots, at: entry.date)
  }

  private var displayItems: [CertificateDisplayItem] {
    CertificateDisplayGrouping.items(
      entry.domains, snapshots: entry.snapshots, at: entry.date)
  }

  private var snapshotByID: [String: CertificateSnapshot] {
    Dictionary(uniqueKeysWithValues: entry.snapshots.map { ($0.id, $0) })
  }

  private var attentionCount: Int {
    WidgetOverview.attentionCount(
      domains: entry.domains, snapshots: entry.snapshots, at: entry.date)
  }

  var body: some View {
    Group {
      if let error = entry.errorMessage, entry.domains.isEmpty {
        WidgetEmptyState(title: "无法读取看板", detail: error, symbol: "exclamationmark.shield")
      } else if ordered.isEmpty {
        WidgetEmptyState(
          title: "添加域名", detail: "打开 CertGlance 开始监控证书", symbol: "plus.circle")
      } else if entry.selection == .pinned(nil) {
        WidgetEmptyState(
          title: "选择监控端点", detail: "编辑小组件，选择要固定关注的域名", symbol: "pin")
      } else if let focus = entry.selection.resolve(in: ordered) {
        switch effectiveFamily {
        case .systemLarge:
          WidgetLargeOverviewView(entry: entry, ordered: ordered)
        case .systemMedium:
          mediumContent
        default:
          smallContent(focus)
        }
      } else {
        WidgetEmptyState(
          title: "端点已移除", detail: "请编辑小组件，重新选择监控端点", symbol: "pin.slash")
      }
    }
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
  }

  private func smallContent(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByID[domain.id]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        if case .pinned = entry.selection {
          Image(systemName: "pin.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        Text(domain.displayName)
          .font(.subheadline.weight(.semibold))
          .lineLimit(2)
          .truncationMode(.middle)
      }
      Spacer(minLength: 5)
      HStack(alignment: .center, spacing: 7) {
        CertificateValidityGauge(snapshot: snapshot, date: entry.date, size: 68)
        VStack(alignment: .leading, spacing: 3) {
          Image(systemName: severity.symbol)
            .font(.caption)
            .foregroundStyle(severity.tint)
            .accessibilityHidden(true)
          Text(smallStatusLabel(snapshot: snapshot, severity: severity))
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      expiryLine(snapshot)
        .padding(.top, 4)
      Spacer(minLength: 0)
      WidgetFreshnessFooter(entry: entry, snapshot: snapshot)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription(domain, snapshot: snapshot, severity: severity))
  }

  private var mediumContent: some View {
    let visibleItems = Array(displayItems.prefix(WidgetOverview.mediumVisibleLimit))
    let hiddenCount = WidgetOverview.hiddenCount(
      total: ordered.count, items: displayItems,
      visibleLimit: WidgetOverview.mediumVisibleLimit)
    return VStack(alignment: .leading, spacing: 3) {
      header
      ForEach(visibleItems.indices, id: \.self) { index in
        if index > 0 {
          Divider()
        }
        WidgetRiskRow(
          item: visibleItems[index], snapshots: snapshotByID, date: entry.date, badgeSize: 32)
      }
      Spacer(minLength: 0)
      if hiddenCount > 0 {
        Text("另有 \(hiddenCount) 个端点")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack {
      Label("证书到期", systemImage: "lock.shield")
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
      } else if entry.reminderErrorMessage != nil {
        Label("提醒异常", systemImage: "bell.slash")
          .font(.caption2.weight(.semibold))
          .accessibilityHint("证书数据已更新，请打开应用查看提醒状态")
      } else {
        Text("\(attentionCount) 需处理 · 共 \(entry.domains.count) 个")
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel("监控 \(entry.domains.count) 个端点，其中 \(attentionCount) 个需处理")
      }
    }
  }

  private func smallStatusLabel(
    snapshot: CertificateSnapshot?, severity: CertificateSeverity
  ) -> String {
    if let snapshot, snapshot.checkState == .failed,
      snapshot.consecutiveFailureCount > 0
    {
      return "失败 \(snapshot.consecutiveFailureCount) 次"
    }
    return severity.label
  }

  @ViewBuilder
  private func expiryLine(_ snapshot: CertificateSnapshot?) -> some View {
    if let snapshot, let expiry = snapshot.expiresAt {
      let prefix = snapshot.checkState == .failed ? "上次已知到期" : "到期"
      Text("\(prefix) \(expiry.formatted(.dateTime.year().month(.abbreviated).day()))")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
  }

  private func accessibilityDescription(
    _ domain: WatchedDomain, snapshot: CertificateSnapshot?, severity: CertificateSeverity
  ) -> String {
    let remaining: String
    if let days = snapshot?.daysRemaining(at: entry.date), severity != .checkFailed,
      severity != .untrusted
    {
      remaining = days <= 0 ? "证书已过期" : "证书剩余 \(days) 天"
    } else {
      remaining = severity.label
    }
    let updateState = entry.errorMessage == nil ? "" : "本次更新失败，"
    let reminderState = entry.reminderErrorMessage == nil ? "" : "提醒同步失败，"
    let failureState: String
    if let snapshot, snapshot.checkState == .failed {
      let lastSuccess =
        snapshot.lastSuccessfulCheckAt.map {
          $0.formatted(date: .abbreviated, time: .shortened)
        } ?? "尚无"
      failureState = "，连续失败 \(snapshot.consecutiveFailureCount) 次，最近成功 \(lastSuccess)"
    } else {
      failureState = ""
    }
    let expiry =
      snapshot?.expiresAt.map {
        let label = snapshot?.checkState == .failed ? "上次已知截止于" : "截止于"
        return "，\(label) \($0.formatted(date: .abbreviated, time: .omitted))"
      } ?? ""
    let selectionState = entry.selection == .automatic ? "" : "固定关注，"
    return
      "\(selectionState)\(updateState)\(reminderState)\(domain.displayName)，\(remaining)\(expiry)\(failureState)"
  }
}
