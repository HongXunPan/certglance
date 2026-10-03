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
    HStack(spacing: 0) {
      metric("正常", value: healthy, symbol: "checkmark.shield.fill", tint: .green)
      Divider()
      metric("需关注", value: attention, symbol: "clock.badge.exclamationmark", tint: .orange)
      Divider()
      metric("异常", value: abnormal, symbol: "exclamationmark.shield.fill", tint: .red)
      Divider()
      metric("待检查", value: unchecked, symbol: "shield.lefthalf.filled", tint: .secondary)
    }
    .padding(.vertical, 13)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
  }

  private func metric(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
    VStack(spacing: 4) {
      HStack(spacing: 5) {
        Image(systemName: symbol)
          .foregroundStyle(tint)
          .accessibilityHidden(true)
        Text("\(value)")
          .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
      }
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) \(value) 个")
  }
}
