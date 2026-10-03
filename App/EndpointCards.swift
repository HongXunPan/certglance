import SwiftUI

struct CertificateFocusCard: View {
  let domain: WatchedDomain
  let snapshot: CertificateSnapshot?
  let date: Date
  let onRemove: () -> Void
  @State private var detailsExpanded = false

  private var severity: CertificateSeverity {
    snapshot?.severity(at: date) ?? .unchecked
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 14) {
        CertificateValidityGauge(snapshot: snapshot, date: date, size: 76)
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(domain.displayName)
              .font(.system(.title3, design: .rounded, weight: .bold))
              .lineLimit(1)
              .truncationMode(.middle)
              .textSelection(.enabled)
              .help(domain.displayName)
            Spacer(minLength: 0)
            removeMenu
          }
          HStack(spacing: 5) {
            Image(systemName: severity.symbol)
              .foregroundStyle(severity.tint)
              .accessibilityHidden(true)
            Text(severity.label)
          }
          .font(.subheadline.weight(.semibold))
          HStack(spacing: 12) {
            expiryLine
            if let snapshot {
              Text("检查 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          if snapshot?.checkState == .trusted,
            snapshot?.validityRemainingFraction(at: date) == nil
          {
            Text("有效期比例待更新")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if snapshot?.checkState == .failed, let snapshot {
            Text("连续失败 \(snapshot.consecutiveFailureCount) 次")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          if let detail = snapshot?.detail {
            Text(detail)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      }
      DisclosureGroup("证书详情", isExpanded: $detailsExpanded) {
        VStack(alignment: .leading, spacing: 5) {
          CertificateValidityDetails(snapshot: snapshot, date: date)
          CertificateCheckDetails(snapshot: snapshot)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .font(.caption)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(severity.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(severity.tint.opacity(0.18), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var expiryLine: some View {
    if let snapshot, let expiry = snapshot.expiresAt {
      Text(
        "\(snapshot.checkState == .failed ? "上次已知到期" : "到期")：\(expiry.formatted(date: .abbreviated, time: .omitted))"
      )
    } else {
      Text("等待首次检查")
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
    .frame(width: 28, height: 28)
    .accessibilityLabel("管理 \(domain.displayName)")
  }
}

struct CertificateEndpointRow: View {
  let domain: WatchedDomain
  let snapshot: CertificateSnapshot?
  let date: Date
  let onRemove: () -> Void

  private var severity: CertificateSeverity {
    snapshot?.severity(at: date) ?? .unchecked
  }

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 5) {
        Text(domain.displayName)
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
          .help(domain.displayName)
        HStack(spacing: 5) {
          Image(systemName: severity.symbol)
            .foregroundStyle(severity.tint)
            .accessibilityHidden(true)
          Text(statusLabel)
          if let snapshot {
            Text("· 检查 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
              .foregroundStyle(.secondary)
          }
        }
        .font(.caption)
        .lineLimit(1)
        if let detail = snapshot?.detail {
          Text(detail)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      VStack(alignment: .trailing, spacing: 3) {
        if let days = snapshot?.daysRemaining(at: date), snapshot?.checkState == .trusted {
          Text("\(max(days, 0)) 天")
            .font(.system(.headline, design: .rounded, weight: .bold).monospacedDigit())
        } else {
          Text("—")
            .font(.headline)
            .foregroundStyle(.secondary)
        }
        if let snapshot, let expiry = snapshot.expiresAt {
          Text(
            "\(snapshot.checkState == .failed ? "已知到期" : "到期") \(expiry.formatted(date: .abbreviated, time: .omitted))"
          )
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        } else {
          Text("等待首次检查")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      .frame(width: 128, alignment: .trailing)
      Menu {
        Button("移除端点", role: .destructive, action: onRemove)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .frame(width: 28, height: 28)
      .accessibilityLabel("管理 \(domain.displayName)")
    }
    .padding(.vertical, 5)
    .accessibilityElement(children: .contain)
  }

  private var statusLabel: String {
    if snapshot?.checkState == .failed, let snapshot {
      return "\(severity.label) · 连续 \(snapshot.consecutiveFailureCount) 次"
    }
    return severity.label
  }
}
