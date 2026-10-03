import SwiftUI

struct WidgetFreshnessFooter: View {
  let entry: SSLExpiryEntry
  let snapshot: CertificateSnapshot?

  @ViewBuilder
  var body: some View {
    if entry.errorMessage != nil {
      Label("更新失败", systemImage: "exclamationmark.triangle")
        .accessibilityHint("打开应用查看并主动重试")
    } else if entry.reminderErrorMessage != nil {
      Label("提醒异常", systemImage: "bell.slash")
        .accessibilityHint("证书数据已更新，请打开应用查看提醒状态")
    } else if let snapshot, snapshot.checkState == .failed {
      if let successfulAt = snapshot.lastSuccessfulCheckAt {
        Text("最近成功 \(successfulAt.formatted(date: .abbreviated, time: .omitted))")
      } else {
        Text("尚无成功检查")
      }
    } else if let snapshot, entry.date.timeIntervalSince(snapshot.checkedAt) >= 86_400 {
      Text("数据待更新 · 上次检查 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .omitted))")
    }
  }
}

struct WidgetCompactEndpointRow: View {
  let domain: WatchedDomain
  let snapshot: CertificateSnapshot?
  let date: Date

  var body: some View {
    let severity = snapshot?.severity(at: date) ?? .unchecked
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Image(systemName: severity.symbol)
          .foregroundStyle(severity.tint)
          .accessibilityHidden(true)
        Text(domain.displayName)
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .truncationMode(.middle)
      }
      HStack(spacing: 4) {
        Text(severity.label).font(.caption2).foregroundStyle(.secondary)
        Spacer(minLength: 0)
        if let days = snapshot?.daysRemaining(at: date), severity != .checkFailed,
          severity != .untrusted
        {
          Text(days <= 0 ? "已过期" : "\(days) 天")
            .font(.caption.weight(.semibold).monospacedDigit())
        }
      }
      if let snapshot, let expiry = snapshot.expiresAt {
        Text(
          "\(snapshot.checkState == .failed ? "已知到期" : "到期") \(expiry.formatted(.dateTime.month(.abbreviated).day()))"
        )
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

struct WidgetEmptyState: View {
  let title: String
  let detail: String
  let symbol: String

  var body: some View {
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
