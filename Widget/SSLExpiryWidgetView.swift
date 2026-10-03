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

  private var snapshotByID: [String: CertificateSnapshot] {
    Dictionary(uniqueKeysWithValues: entry.snapshots.map { ($0.id, $0) })
  }

  var body: some View {
    Group {
      if let error = entry.errorMessage, entry.domains.isEmpty {
        WidgetEmptyState(title: "无法读取看板", detail: error, symbol: "exclamationmark.shield")
      } else if ordered.isEmpty {
        WidgetEmptyState(
          title: "添加域名", detail: "打开 CertGlance 开始监控证书", symbol: "plus.circle")
      } else if let focus = ordered.first {
        if effectiveFamily == .systemMedium { mediumContent(focus) } else { smallContent(focus) }
      }
    }
    .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
  }

  private func smallContent(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByID[domain.id]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return VStack(alignment: .leading, spacing: 0) {
      Text(domain.displayName)
        .font(.subheadline.weight(.semibold))
        .lineLimit(2)
        .truncationMode(.middle)
      Spacer(minLength: 5)
      HStack(alignment: .center, spacing: 9) {
        CertificateValidityGauge(snapshot: snapshot, date: entry.date, size: 76)
        statusLine(severity: severity)
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

  private func mediumContent(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByID[domain.id]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return VStack(alignment: .leading, spacing: 0) {
      header
      Divider().padding(.vertical, 8)
      HStack(alignment: .top, spacing: 14) {
        VStack(alignment: .leading, spacing: 5) {
          Text(domain.displayName)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.middle)
          HStack(spacing: 8) {
            CertificateValidityGauge(snapshot: snapshot, date: entry.date, size: 68)
            statusLine(severity: severity)
          }
          expiryLine(snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if ordered.count > 1 {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ordered.dropFirst().prefix(2))) { other in
              WidgetCompactEndpointRow(
                domain: other, snapshot: snapshotByID[other.id], date: entry.date)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Spacer(minLength: 0)
      if let snapshot {
        VStack(alignment: .leading, spacing: 2) {
          Text("最近检查：\(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
          if snapshot.checkState == .failed {
            let lastSuccess =
              snapshot.lastSuccessfulCheckAt.map {
                $0.formatted(date: .abbreviated, time: .omitted)
              } ?? "尚无"
            Text("最近成功：\(lastSuccess) · 连续失败 \(snapshot.consecutiveFailureCount) 次")
          }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
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
        Text("\(entry.domains.count)")
          .font(.caption.weight(.semibold).monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityLabel("监控 \(entry.domains.count) 个域名")
      }
    }
  }

  private func statusLine(severity: CertificateSeverity) -> some View {
    HStack(spacing: 5) {
      Image(systemName: severity.symbol)
        .foregroundStyle(severity.tint)
        .accessibilityHidden(true)
      Text(severity.label)
        .foregroundStyle(.primary)
      Spacer(minLength: 2)
    }
    .font(.caption2.weight(.medium))
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
    return
      "\(updateState)\(reminderState)\(domain.displayName)，\(remaining)\(expiry)\(failureState)"
  }
}
