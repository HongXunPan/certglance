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
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 5) {
        Image(systemName: severity.symbol)
          .foregroundStyle(severity.tint)
          .accessibilityHidden(true)
        Text(domain.displayName)
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        if let days = snapshot?.daysRemaining(at: date), snapshot?.checkState == .trusted {
          Text("\(max(days, 0)) 天")
            .font(.caption.weight(.semibold).monospacedDigit())
        } else {
          Text("—")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      HStack(spacing: 5) {
        if let snapshot, let expiry = snapshot.expiresAt {
          Text(
            "\(snapshot.checkState == .failed ? "已知到期" : "到期") \(expiry.formatted(.dateTime.month(.abbreviated).day()))"
          )
        } else {
          Text("等待首次检查")
        }
        Spacer(minLength: 4)
        Text(severity.label)
          .foregroundStyle(.primary)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }
}

struct WidgetCompactDisplayRow: View {
  let item: CertificateDisplayItem
  let snapshots: [String: CertificateSnapshot]
  let date: Date

  var body: some View {
    if item.isGroup {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Image(systemName: item.severity.symbol)
            .foregroundStyle(item.severity.tint)
            .accessibilityHidden(true)
          if let day = item.expiryDay {
            Text(
              "\(day.formatted(.dateTime.month(.abbreviated).day())) 到期 · \(item.domains.count) 个"
            )
            .font(.caption.weight(.semibold))
            .lineLimit(1)
          }
          Spacer(minLength: 4)
          Text(minimumDays > 0 ? "\(minimumDays) 天" : "已过期")
            .font(.caption.weight(.semibold).monospacedDigit())
        }
        Text(item.domains.prefix(2).map(\.displayName).joined(separator: " · "))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "\(item.domains.count) 个端点同日到期，\(remainingDescription)：\(item.domains.map(\.displayName).joined(separator: "、"))"
      )
    } else {
      WidgetCompactEndpointRow(
        domain: item.primary, snapshot: snapshots[item.primary.id], date: date)
    }
  }

  private var minimumDays: Int {
    max(0, item.minimumDays(at: date, snapshots: snapshots) ?? 0)
  }

  private var remainingDescription: String {
    minimumDays > 0 ? "最短剩余 \(minimumDays) 天" : "已过期"
  }
}

struct WidgetExpiryGroupFocus: View {
  let item: CertificateDisplayItem
  let snapshots: [String: CertificateSnapshot]
  let date: Date
  let compact: Bool

  var body: some View {
    HStack(alignment: .center, spacing: compact ? 9 : 14) {
      VStack(spacing: 0) {
        Text(minimumDays > 0 ? "\(minimumDays)" : "0")
          .font(.system(compact ? .title2 : .largeTitle, design: .rounded, weight: .bold))
          .monospacedDigit()
        Text(minimumDays > 0 ? "天" : "已过期")
          .font(.caption)
      }
      .foregroundStyle(item.severity.tint)
      .frame(width: compact ? 50 : 78)
      VStack(alignment: .leading, spacing: compact ? 2 : 4) {
        if let day = item.expiryDay {
          Text(
            "\(day.formatted(.dateTime.month(.abbreviated).day())) 到期 · \(item.domains.count) 个端点"
          )
          .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
          .lineLimit(1)
        }
        ForEach(Array(item.domains.prefix(2))) { domain in
          Text(domain.displayName)
            .font(compact ? .caption : .subheadline)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        if item.domains.count > 2 {
          Text("另有 \(item.domains.count - 2) 个")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "\(item.domains.count) 个端点同日到期，\(remainingDescription)：\(item.domains.map(\.displayName).joined(separator: "、"))"
    )
  }

  private var minimumDays: Int {
    max(0, item.minimumDays(at: date, snapshots: snapshots) ?? 0)
  }

  private var remainingDescription: String {
    minimumDays > 0 ? "最短剩余 \(minimumDays) 天" : "已过期"
  }
}

struct WidgetEmptyState: View {
  let title: String
  let detail: String
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Spacer(minLength: 0)
      Image(systemName: symbol)
        .font(.title2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text(title).font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
      Spacer(minLength: 0)
    }
  }
}
