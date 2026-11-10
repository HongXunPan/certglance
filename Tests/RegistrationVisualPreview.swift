import SwiftUI
import WidgetKit

@MainActor
enum RegistrationVisualPreview {
  static func renderAll(output: URL) throws {
    let date = Date(timeIntervalSince1970: 1_790_000_000)
    let domains = ["example.com", "very-long-registered-domain-for-layout.example"].map {
      RegisteredDomain(hostname: $0, addedAt: date)
    }
    let snapshots = [
      RegistrationSnapshot(
        hostname: domains[0].id, checkedAt: date,
        dates: RegistrationDates(
          registrar: date.addingTimeInterval(7 * 86_400),
          registry: date.addingTimeInterval(372 * 86_400)),
        checkState: .available, sources: ["https://rdap.example/domain/example.com"]),
      RegistrationSnapshot(
        hostname: domains[1].id, checkedAt: date,
        dates: RegistrationDates(registry: date.addingTimeInterval(30 * 86_400)),
        checkState: .failed, detail: "查询超时，当前显示上次已知日期。",
        lastSuccessfulCheckAt: date.addingTimeInterval(-3 * 86_400)),
    ]
    let entry = RegistrationEntry(date: date, domains: domains, snapshots: snapshots, error: nil)
    for scheme in [ColorScheme.light, .dark] {
      let suffix = scheme == .light ? "浅色" : "深色"
      let failed = RegistrationSnapshot(
        hostname: domains[1].id, checkedAt: date,
        dates: RegistrationDates(registry: date.addingTimeInterval(-86_400)),
        checkState: .failed, lastSuccessfulCheckAt: date.addingTimeInterval(-3 * 86_400))
      let stress = RegistrationEntry(
        date: date, domains: domains, snapshots: [snapshots[0], failed], error: nil)
      let smallStress = RegistrationWidgetView(entry: stress, previewFamily: .systemSmall)
        .padding(12).frame(width: 164, height: 164)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, scheme)
        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
      try CertGlanceVisualQA.save(smallStress, name: "注册小号-长域名失败-\(suffix)", output: output)
      for family in [WidgetFamily.systemSmall, .systemMedium] {
        let small = family == .systemSmall
        let view = RegistrationWidgetView(entry: entry, previewFamily: family)
          .padding(12)
          .frame(width: small ? 164 : 344, height: 164)
          .background(Color(nsColor: .windowBackgroundColor))
          .environment(\.colorScheme, scheme)
          .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
        try CertGlanceVisualQA.save(
          view, name: "注册\(small ? "小号" : "中号")-\(suffix)", output: output)
      }
      let rows = VStack(alignment: .leading, spacing: 16) {
        Text("域名注册到期").font(.title2.bold())
        Text("固定假数据 · 不代表真实域名状态").foregroundStyle(.secondary)
        ForEach(Array(zip(domains, snapshots)), id: \.0.id) { domain, snapshot in
          RegistrationDomainRow(domain: domain, snapshot: snapshot, date: date, remove: {})
          Divider()
        }
      }
      .padding(24)
      .frame(width: 680)
      .background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, scheme)
      try CertGlanceVisualQA.save(rows, name: "注册列表-\(suffix)", output: output)
    }
  }
}
