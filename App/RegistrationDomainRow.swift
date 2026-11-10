import SwiftUI

struct RegistrationDomainRow: View {
  let domain: RegisteredDomain
  let snapshot: RegistrationSnapshot?
  let date: Date
  let remove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top) {
        Label(domain.hostname, systemImage: "globe")
          .font(.headline)
          .textSelection(.enabled)
        Spacer()
        Button(role: .destructive, action: remove) { Image(systemName: "trash") }
          .buttonStyle(.borderless)
          .accessibilityLabel("移除注册域名 \(domain.hostname)")
      }
      if let snapshot {
        Text(snapshot.label(at: date))
          .foregroundStyle(snapshot.needsAttention(at: date) ? Color.orange : Color.primary)
        if snapshot.dates.hasDifferentDates {
          Text("注册局与注册商日期不同，请核对续费期限。")
            .font(.caption).foregroundStyle(.orange)
        }
        if let expiry = snapshot.dates.preferred, let days = snapshot.daysRemaining(at: date) {
          HStack {
            Text("\(days) 天").font(.title3.monospacedDigit())
            Text(
              "\(snapshot.checkState == .failed ? "上次已知" : "")\(snapshot.dates.basis)：\(expiry.formatted(date: .numeric, time: .omitted))"
            )
          }
        }
        if let detail = snapshot.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        DisclosureGroup("日期来源与检查详情") {
          VStack(alignment: .leading, spacing: 6) {
            if let registrar = snapshot.dates.registrar { Text("注册商到期日：\(registrar.formatted())") }
            if let registry = snapshot.dates.registry { Text("注册局到期日：\(registry.formatted())") }
            if let reported = snapshot.dates.reported { Text("服务报告日期：\(reported.formatted())") }
            Text("最近尝试：\(snapshot.checkedAt.formatted())")
            if let success = snapshot.lastSuccessfulCheckAt {
              Text("最近取得日期：\(success.formatted())")
            }
            ForEach(snapshot.sources, id: \.self) { Text($0).textSelection(.enabled) }
            if date.timeIntervalSince(snapshot.lastSuccessfulCheckAt ?? .distantPast) > 48 * 3_600 {
              Text("日期数据较旧或尚未获取，请主动检查。")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      } else {
        Text("待检查").foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 8)
  }
}
