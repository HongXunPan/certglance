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
        stateView(title: "无法读取看板", detail: error, symbol: "exclamationmark.shield")
      } else if ordered.isEmpty {
        stateView(title: "添加域名", detail: "打开 CertGlance 开始监控证书", symbol: "plus.circle")
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
      header
      Spacer(minLength: 3)
      HStack(spacing: 8) {
        CertificateCountdownGauge(snapshot: snapshot, date: entry.date, size: 64)
        VStack(alignment: .leading, spacing: 3) {
          Text(severity.label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(severity.tint)
          expiryLine(snapshot)
        }
      }
      Text(domain.displayName)
        .font(.caption.weight(.semibold))
        .lineLimit(2)
        .truncationMode(.middle)
        .padding(.top, 3)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityDescription(domain, snapshot: snapshot, severity: severity))
  }

  private func mediumContent(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByID[domain.id]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return VStack(alignment: .leading, spacing: 0) {
      header
      Divider().padding(.vertical, 10)
      HStack(alignment: .top, spacing: 18) {
        HStack(alignment: .center, spacing: 8) {
          CertificateCountdownGauge(snapshot: snapshot, date: entry.date, size: 68)
          VStack(alignment: .leading, spacing: 5) {
            Text(domain.displayName)
              .font(.subheadline.weight(.semibold))
              .lineLimit(2)
              .truncationMode(.middle)
            statusLine(severity: severity)
            expiryLine(snapshot)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if ordered.count > 1 {
          VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ordered.dropFirst().prefix(2))) { other in
              compactRow(other)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      Spacer(minLength: 0)
      if let snapshot {
        Text("最近检查：\(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack {
      Label("CertGlance", systemImage: "lock.shield")
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

  private func compactRow(_ domain: WatchedDomain) -> some View {
    let snapshot = snapshotByID[domain.id]
    let severity = snapshot?.severity(at: entry.date) ?? .unchecked
    return VStack(alignment: .leading, spacing: 3) {
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
        if let days = snapshot?.daysRemaining(at: entry.date), severity != .checkFailed,
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

  private func stateView(title: String, detail: String, symbol: String) -> some View {
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
    let expiry =
      snapshot?.expiresAt.map {
        let label = snapshot?.checkState == .failed ? "上次已知截止于" : "截止于"
        return "，\(label) \($0.formatted(date: .abbreviated, time: .omitted))"
      } ?? ""
    return "\(updateState)\(domain.displayName)，\(remaining)\(expiry)"
  }
}
