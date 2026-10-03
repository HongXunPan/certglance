import SwiftUI

struct CertificateFocusCard: View {
  let domain: WatchedDomain
  let snapshot: CertificateSnapshot?
  let date: Date
  let onRemove: () -> Void

  private var severity: CertificateSeverity {
    snapshot?.severity(at: date) ?? .unchecked
  }

  var body: some View {
    HStack(alignment: .center, spacing: 24) {
      VStack(spacing: 7) {
        CertificateValidityGauge(snapshot: snapshot, date: date, size: 118)
        Text(gaugeCaption)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .frame(width: 130)

      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 8) {
          Text(domain.displayName)
            .font(.system(.title2, design: .rounded, weight: .bold))
            .lineLimit(2)
            .truncationMode(.middle)
            .textSelection(.enabled)
          Spacer(minLength: 0)
          removeMenu
        }
        Label(severity.label, systemImage: severity.symbol)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(severity.tint)
        expiryLine
        CertificateValidityDetails(snapshot: snapshot, date: date)
        if let detail = snapshot?.detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        CertificateCheckDetails(snapshot: snapshot, compact: false)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    .accessibilityElement(children: .contain)
  }

  private var gaugeCaption: String {
    switch severity {
    case .expired: return "有效期已结束"
    case .checkFailed: return "检查失败"
    case .untrusted: return "信任异常"
    case .unchecked: return "尚未检查"
    default:
      return snapshot?.validityRemainingFraction(at: date) == nil ? "有效期待更新" : "有效期剩余"
    }
  }

  @ViewBuilder
  private var expiryLine: some View {
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

  private var removeMenu: some View {
    Menu {
      Button("移除端点", role: .destructive, action: onRemove)
    } label: {
      Image(systemName: "ellipsis.circle")
    }
    .menuStyle(.borderlessButton)
    .accessibilityLabel("管理 \(domain.displayName)")
  }
}

struct CertificateCompactCard: View {
  let domain: WatchedDomain
  let snapshot: CertificateSnapshot?
  let date: Date
  let onRemove: () -> Void

  private var severity: CertificateSeverity {
    snapshot?.severity(at: date) ?? .unchecked
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 8) {
        Image(systemName: severity.symbol)
          .foregroundStyle(severity.tint)
          .accessibilityHidden(true)
        Text(domain.displayName)
          .font(.headline)
          .lineLimit(2)
          .truncationMode(.middle)
          .textSelection(.enabled)
        Spacer(minLength: 0)
        Menu {
          Button("移除端点", role: .destructive, action: onRemove)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("管理 \(domain.displayName)")
      }

      HStack(alignment: .firstTextBaseline) {
        Text(severity.label)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(severity.tint)
        Spacer(minLength: 4)
        if let days = snapshot?.daysRemaining(at: date), snapshot?.checkState == .trusted {
          Text(days <= 0 ? "已过期" : "剩余 \(days) 天")
            .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
        }
      }

      if let snapshot, let expiry = snapshot.expiresAt {
        Text(
          "\(snapshot.checkState == .failed ? "上次已知到期" : "到期")：\(expiry.formatted(date: .abbreviated, time: .omitted))"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      } else {
        Text("等待首次检查")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if let detail = snapshot?.detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      CertificateCheckDetails(snapshot: snapshot, compact: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .contain)
  }
}
