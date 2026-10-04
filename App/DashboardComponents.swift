import SwiftUI

struct DashboardSummary: View {
  let domains: [WatchedDomain]
  let snapshots: [CertificateSnapshot]
  let date: Date

  private var counts: [CertificateSeverity: Int] {
    let indexed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    var values: [CertificateSeverity: Int] = [:]
    for domain in domains {
      let severity = indexed[domain.id]?.severity(at: date) ?? .unchecked
      values[severity, default: 0] += 1
    }
    return values
  }

  var body: some View {
    let healthy = counts[.healthy, default: 0]
    let attention =
      counts[.watch, default: 0] + counts[.soon, default: 0]
      + counts[.critical, default: 0]
    let abnormal =
      counts[.expired, default: 0] + counts[.checkFailed, default: 0]
      + counts[.untrusted, default: 0]
    let unchecked = counts[.unchecked, default: 0]
    HStack(spacing: 8) {
      metric("异常", value: abnormal, symbol: "exclamationmark.shield.fill", tint: .red)
      metric("需关注", value: attention, symbol: "clock.badge.exclamationmark", tint: .orange)
      metric("正常", value: healthy, symbol: "checkmark.shield.fill", tint: .green)
      metric("待检查", value: unchecked, symbol: "shield.lefthalf.filled", tint: .secondary)
    }
    .padding(.vertical, 6)
  }

  private func metric(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Text("\(value)")
        .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) \(value) 个")
  }
}

struct CertificateDetailsDisclosure<Content: View>: View {
  let title: String
  @Binding var isExpanded: Bool
  let content: Content

  init(
    _ title: String, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self._isExpanded = isExpanded
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        isExpanded.toggle()
      } label: {
        HStack(spacing: 6) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2.weight(.semibold))
            .frame(width: 12)
            .accessibilityHidden(true)
          Text(title)
        }
        .font(.caption.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(title)
      .accessibilityValue(isExpanded ? "已展开" : "已收起")
      .accessibilityHint(isExpanded ? "按下以收起详情" : "按下以展开详情")
      if isExpanded {
        content
      }
    }
  }
}

struct CertificateCheckDetails: View {
  let snapshot: CertificateSnapshot?

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      if let snapshot {
        Text("最近检查：\(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
        if snapshot.checkState == .failed {
          if let successfulAt = snapshot.lastSuccessfulCheckAt {
            Text("最近成功：\(successfulAt.formatted(date: .abbreviated, time: .shortened))")
          } else {
            Text("尚无成功检查")
          }
          Text("连续失败：\(snapshot.consecutiveFailureCount) 次")
        }
      } else {
        Text("尚未检查")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }
}

struct CertificateValidityDetails: View {
  let snapshot: CertificateSnapshot?
  let date: Date

  var body: some View {
    if let snapshot, snapshot.checkState == .trusted,
      let validFrom = snapshot.validFrom, let expiry = snapshot.expiresAt,
      let fraction = snapshot.validityRemainingFraction(at: date)
    {
      VStack(alignment: .leading, spacing: 3) {
        Text("圆环：证书完整有效期中剩余 \(Int((fraction * 100).rounded()))%")
        Text(
          "有效期：\(validFrom.formatted(date: .abbreviated, time: .omitted)) 至 \(expiry.formatted(date: .abbreviated, time: .omitted))"
        )
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .accessibilityElement(children: .combine)
    }
  }
}
