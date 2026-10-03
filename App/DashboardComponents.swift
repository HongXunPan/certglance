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
    HStack(spacing: 12) {
      metric("正常", value: healthy, symbol: "checkmark.shield.fill", tint: .green)
      metric("需关注", value: attention, symbol: "clock.badge.exclamationmark", tint: .orange)
      metric("异常", value: abnormal, symbol: "exclamationmark.shield.fill", tint: .red)
      metric("待检查", value: unchecked, symbol: "shield.lefthalf.filled", tint: .secondary)
    }
  }

  private func metric(_ title: String, value: Int, symbol: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      Image(systemName: symbol)
        .font(.title3)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      Text("\(value)")
        .font(.system(.title, design: .rounded, weight: .bold).monospacedDigit())
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(title) \(value) 个")
  }
}

struct CertificateDashboardCard: View {
  let domain: WatchedDomain
  let snapshot: CertificateSnapshot?
  let date: Date
  let onRemove: () -> Void

  private var severity: CertificateSeverity {
    snapshot?.severity(at: date) ?? .unchecked
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        VStack(spacing: 1) {
          CertificateCountdownGauge(snapshot: snapshot, date: date, size: 82)
          Text("30 天窗口")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 8) {
          Label(severity.label, systemImage: severity.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(severity.tint)
          Button("移除", role: .destructive, action: onRemove)
            .buttonStyle(.borderless)
            .accessibilityLabel("删除 \(domain.displayName)")
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(domain.displayName)
          .font(.system(.headline, design: .rounded))
          .lineLimit(2)
          .truncationMode(.middle)
          .textSelection(.enabled)
        if let snapshot, let expiry = snapshot.expiresAt {
          Text(
            "\(snapshot.checkState == .failed ? "上次已知到期" : "到期")：\(expiry.formatted(date: .abbreviated, time: .omitted))"
          )
          .font(.subheadline)
        } else {
          Text("等待首次检查")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      if let detail = snapshot?.detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Divider()
      Text(
        snapshot.map { "最近检查：\($0.checkedAt.formatted(date: .abbreviated, time: .shortened))" }
          ?? "尚未检查"
      )
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    .accessibilityElement(children: .contain)
  }
}
