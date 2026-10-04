import SwiftUI

struct WidgetRiskRow: View {
  let item: CertificateDisplayItem
  let snapshots: [String: CertificateSnapshot]
  let date: Date
  let badgeSize: CGFloat

  private var snapshot: CertificateSnapshot? { snapshots[item.primary.id] }

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: item.severity.symbol)
            .font(.caption)
            .foregroundStyle(item.severity.tint)
            .accessibilityHidden(true)
          if item.isGroup {
            Text(groupHeading)
              .font(.caption.weight(.semibold))
              .lineLimit(1)
              .minimumScaleFactor(0.85)
          } else {
            Text(item.primary.displayName)
              .font(.subheadline.weight(.semibold))
              .lineLimit(1)
              .truncationMode(.middle)
          }
        }
        if item.isGroup {
          HStack(spacing: 6) {
            ForEach(Array(item.domains.prefix(2))) { domain in
              Text(domain.displayName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          if isStale {
            Text("组内有数据待更新")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        } else {
          HStack(spacing: 6) {
            Text(detail)
              .lineLimit(1)
              .truncationMode(.middle)
            Spacer(minLength: 4)
            if isStale {
              Text("待更新")
                .fixedSize(horizontal: true, vertical: false)
            }
          }
          .font(.caption2)
          .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let remainingDays {
        WidgetRemainingDayBadge(
          days: remainingDays, size: badgeSize, tint: item.severity.tint,
          isHealthy: item.severity == .healthy)
      } else {
        Text(metric)
          .font(.caption.weight(.semibold))
          .foregroundStyle(item.severity.tint)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityDescription)
  }

  private var groupHeading: String {
    let expiry = item.expiryDay.map(displayDate) ?? "日期未知"
    return "\(item.severity.label) · \(expiry)到期 · \(item.domains.count) 个"
  }

  private var metric: String {
    if item.isGroup {
      guard let days = item.minimumDays(at: date, snapshots: snapshots) else { return "待检查" }
      return days <= 0 ? "已过期" : "\(days) 天"
    }
    switch item.severity {
    case .expired, .checkFailed, .untrusted, .unchecked:
      return item.severity.label
    case .critical, .soon, .watch, .healthy:
      guard let days = snapshot?.daysRemaining(at: date) else { return item.severity.label }
      return "\(days) 天"
    }
  }

  private var remainingDays: Int? {
    guard
      item.severity == .critical || item.severity == .soon
        || item.severity == .watch || item.severity == .healthy
    else { return nil }
    let days =
      item.isGroup
      ? item.minimumDays(at: date, snapshots: snapshots)
      : snapshot?.daysRemaining(at: date)
    guard let days, days > 0 else { return nil }
    return days
  }

  private var detail: String {
    guard let snapshot else { return "等待首次检查" }
    let expiry = snapshot.expiresAt.map(displayDate)
    if snapshot.checkState == .failed {
      let known = expiry.map { "已知到期 \($0)" } ?? "无已知到期日"
      return "连续失败 \(snapshot.consecutiveFailureCount) 次 · \(known)"
    }
    let due = expiry.map { "到期 \($0)" } ?? "到期日未知"
    if item.severity == .expired || item.severity == .untrusted {
      return due
    }
    return "\(item.severity.label) · \(due)"
  }

  private func displayDate(_ expiry: Date) -> String {
    if Calendar.current.isDate(expiry, equalTo: date, toGranularity: .year) {
      return expiry.formatted(.dateTime.month().day())
    }
    return expiry.formatted(.dateTime.year().month().day())
  }

  private var isStale: Bool {
    item.domains.contains { domain in
      guard let snapshot = snapshots[domain.id], snapshot.checkState != .failed else {
        return false
      }
      return date.timeIntervalSince(snapshot.checkedAt) >= 86_400
    }
  }

  private var accessibilityDescription: String {
    let names = item.domains.map(\.displayName).joined(separator: "、")
    let subject = item.isGroup ? "\(item.domains.count) 个同日到期端点：\(names)" : names
    let freshness = isStale ? "，数据待更新" : ""
    let detailText = item.isGroup ? groupHeading : detail
    let remaining = item.isGroup && remainingDays != nil ? "最短剩余 \(metric)" : metric
    return "\(subject)，\(item.severity.label)，\(remaining)，\(detailText)\(freshness)"
  }
}

private struct WidgetRemainingDayBadge: View {
  let days: Int
  let size: CGFloat
  let tint: Color
  let isHealthy: Bool

  var body: some View {
    VStack(spacing: -2) {
      Text("\(days)")
        .font(.system(size: size * 0.36, weight: .bold, design: .rounded).monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.55)
      Text("天")
        .font(.system(size: size * 0.23, weight: .medium))
    }
    .foregroundStyle(isHealthy ? Color.primary : tint)
    .frame(width: size - 8, height: size - 8)
    .background {
      Circle()
        .strokeBorder(tint.opacity(isHealthy ? 0.65 : 0.8), lineWidth: 2)
        .frame(width: size, height: size)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
