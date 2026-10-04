import SwiftUI

struct ExpiryGroupCard: View {
  let item: CertificateDisplayItem
  let snapshots: [String: CertificateSnapshot]
  let date: Date
  let onRemove: (String) -> Void
  @State private var detailsExpanded = false

  private var minimumDays: Int {
    item.minimumDays(at: date, snapshots: snapshots) ?? 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack(alignment: .firstTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
          if let day = item.expiryDay {
            Text(day.formatted(.dateTime.year().month().day()))
              .font(.headline)
          }
          Text("\(item.domains.count) 个端点同日到期")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        if minimumDays > 0 {
          Text("\(minimumDays) 天")
            .font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
            .foregroundStyle(item.severity.tint)
            .accessibilityLabel("最短剩余 \(minimumDays) 天")
        } else {
          Text("已过期")
            .font(.headline)
            .foregroundStyle(item.severity.tint)
        }
      }
      ForEach(Array(item.domains.prefix(2))) { domain in
        HStack(spacing: 7) {
          Image(systemName: item.severity.symbol)
            .foregroundStyle(item.severity.tint)
            .accessibilityHidden(true)
          Text(domain.displayName)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(domain.displayName)
          Spacer(minLength: 4)
          if let snapshot = snapshots[domain.id] {
            Text("检查 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      }
      if item.domains.count > 2 {
        Text("另有 \(item.domains.count - 2) 个端点")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      DisclosureGroup("查看各端点详情", isExpanded: $detailsExpanded) {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(item.domains) { domain in
            CertificateEndpointRow(
              domain: domain, snapshot: snapshots[domain.id], date: date,
              onRemove: { onRemove(domain.id) })
            if domain.id != item.domains.last?.id { Divider() }
          }
        }
      }
      .font(.caption)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(item.severity.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .strokeBorder(item.severity.tint.opacity(0.18), lineWidth: 1)
    }
    .accessibilityElement(children: .contain)
  }
}
