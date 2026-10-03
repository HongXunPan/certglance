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
        Text(snapshot?.validityRemainingFraction(at: date) == nil ? "有效期待更新" : "有效期剩余")
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
        if let detail = snapshot?.detail {
          Text(detail)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        Text(
          snapshot.map { "最近检查：\($0.checkedAt.formatted(date: .abbreviated, time: .shortened))" }
            ?? "尚未检查"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    .accessibilityElement(children: .contain)
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
      Text(
        snapshot.map { "最近检查：\($0.checkedAt.formatted(date: .abbreviated, time: .shortened))" }
          ?? "尚未检查"
      )
      .font(.caption2)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    .accessibilityElement(children: .contain)
  }
}
