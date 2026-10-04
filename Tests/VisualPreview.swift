import AppKit
import SwiftUI
import WidgetKit

// 此入口由视觉预览脚本单独编译，不读取真实监控数据或系统小组件配置。
struct SSLExpiryEntry {
  let date: Date
  let domains: [WatchedDomain]
  let snapshots: [CertificateSnapshot]
  let errorMessage: String?
  let reminderErrorMessage: String?
  let selection: WidgetDisplaySelection
}

@MainActor
@main
struct CertGlanceVisualQA {
  static func main() throws {
    _ = NSApplication.shared
    let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

    let date = Date(timeIntervalSince1970: 1_780_000_000)
    let normal = normalFixture(at: date)
    let stress = stressFixture(at: date)
    let overflow = overflowFixture(from: normal, at: date)
    precondition(Set(normal.domains.map(\.id)).count == normal.domains.count, "预览端点不可重复")
    precondition(Set(stress.domains.map(\.id)).count == stress.domains.count, "预览端点不可重复")
    precondition(Set(overflow.domains.map(\.id)).count == overflow.domains.count, "预览端点不可重复")

    try renderDashboard("主界面-常态-浅色", fixture: normal, scheme: .light, output: output)
    try renderDashboard("主界面-复杂-深色", fixture: stress, scheme: .dark, output: output)
    try renderWidget(
      "自动小号-浅色", entry: normal, family: .systemSmall,
      width: 164, height: 164, scheme: .light, output: output)
    try renderWidget(
      "自动小号-过期-深色", entry: stress, family: .systemSmall,
      width: 164, height: 164, scheme: .dark, output: output)
    try renderWidget(
      "自动中号-浅色", entry: normal, family: .systemMedium,
      width: 344, height: 164, scheme: .light, output: output)
    try renderWidget(
      "自动大号-浅色", entry: normal, family: .systemLarge,
      width: 344, height: 344, scheme: .light, output: output)
    try renderWidget(
      "固定小号-深色",
      entry: SSLExpiryEntry(
        date: date, domains: normal.domains, snapshots: normal.snapshots,
        errorMessage: nil, reminderErrorMessage: nil,
        selection: .pinned(normal.domains[2].id)),
      family: .systemSmall, width: 164, height: 164, scheme: .dark, output: output)
    try renderWidget(
      "固定小号-长域名-深色",
      entry: SSLExpiryEntry(
        date: date, domains: normal.domains, snapshots: normal.snapshots,
        errorMessage: nil, reminderErrorMessage: nil,
        selection: .pinned(normal.domains[3].id)),
      family: .systemSmall, width: 164, height: 164, scheme: .dark, output: output)
    try renderWidget(
      "固定小号-失败-浅色",
      entry: SSLExpiryEntry(
        date: date, domains: stress.domains, snapshots: stress.snapshots,
        errorMessage: nil, reminderErrorMessage: nil,
        selection: .pinned(stress.domains[1].id)),
      family: .systemSmall, width: 164, height: 164, scheme: .light, output: output)
    try renderWidget(
      "自动中号-复杂-深色", entry: stress, family: .systemMedium,
      width: 344, height: 164, scheme: .dark, output: output)
    try renderWidget(
      "自动中号-溢出-浅色", entry: overflow, family: .systemMedium,
      width: 344, height: 164, scheme: .light, output: output)
    try renderWidget(
      "自动大号-复杂-深色", entry: stress, family: .systemLarge,
      width: 344, height: 344, scheme: .dark, output: output)
    try renderWidget(
      "自动大号-溢出-浅色", entry: overflow, family: .systemLarge,
      width: 344, height: 344, scheme: .light, output: output)
    for count in [1, 3, 5] {
      let subset = SSLExpiryEntry(
        date: date, domains: Array(normal.domains.prefix(count)),
        snapshots: Array(normal.snapshots.prefix(count)),
        errorMessage: nil, reminderErrorMessage: nil, selection: .automatic)
      try renderWidget(
        "自动大号-\(count)端点-浅色", entry: subset, family: .systemLarge,
        width: 344, height: 344, scheme: .light, output: output)
    }
    let singleLong = SSLExpiryEntry(
      date: date, domains: [normal.domains[3]], snapshots: [normal.snapshots[3]],
      errorMessage: nil, reminderErrorMessage: nil, selection: .automatic)
    try renderWidget(
      "自动大号-单个长域名-浅色", entry: singleLong, family: .systemLarge,
      width: 344, height: 344, scheme: .light, output: output)
  }

  private static func renderDashboard(
    _ name: String, fixture: SSLExpiryEntry, scheme: ColorScheme, output: URL
  ) throws {
    let items = CertificateDisplayGrouping.items(
      fixture.domains, snapshots: fixture.snapshots, at: fixture.date)
    let indexed = Dictionary(uniqueKeysWithValues: fixture.snapshots.map { ($0.id, $0) })
    let view = VStack(alignment: .leading, spacing: 12) {
      Text("证书总览")
        .font(.system(.title2, design: .rounded, weight: .bold))
      Text("监控 \(fixture.domains.count) 个 HTTPS 端点 · 按风险排序")
        .font(.subheadline)
        .foregroundStyle(.secondary)
      Divider()
      DashboardSummary(
        domains: fixture.domains, snapshots: fixture.snapshots, date: fixture.date)
      Text("监控端点")
        .font(.headline)
      if let focus = items.first {
        Text("优先关注")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        if focus.isGroup {
          ExpiryGroupCard(
            item: focus, snapshots: indexed, date: fixture.date, onRemove: { _ in })
        } else {
          CertificateFocusCard(
            domain: focus.primary, snapshot: indexed[focus.primary.id],
            date: fixture.date, onRemove: {})
        }
      }
      if items.count > 1 {
        Text("其他端点")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
        ForEach(Array(items.dropFirst())) { item in
          if item.isGroup {
            ExpiryGroupCard(
              item: item, snapshots: indexed, date: fixture.date, onRemove: { _ in })
          } else {
            CertificateEndpointRow(
              domain: item.primary, snapshot: indexed[item.primary.id],
              date: fixture.date, onRemove: {})
          }
          Divider()
        }
      }
      Spacer(minLength: 0)
    }
    .padding(24)
    .frame(width: 620, height: 850, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(\.colorScheme, scheme)
    try save(view, name: name, output: output)
  }

  private static func renderWidget(
    _ name: String, entry: SSLExpiryEntry, family: WidgetFamily,
    width: CGFloat, height: CGFloat, scheme: ColorScheme, output: URL
  ) throws {
    let view = SSLExpiryWidgetView(entry: entry, previewFamily: family)
      .padding(12)
      .frame(width: width, height: height)
      .background(Color(nsColor: .windowBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 28))
      .environment(\.colorScheme, scheme)
    try save(view, name: name, output: output)
  }

  private static func save<V: View>(_ view: V, name: String, output: URL) throws {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    renderer.isOpaque = true
    guard let image = renderer.cgImage,
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    else { throw NSError(domain: "视觉预览", code: 1) }
    try data.write(to: output.appendingPathComponent("\(name).png"))
    print("[预览] \(name)：\(image.width)×\(image.height)")
  }

  private static func normalFixture(at date: Date) -> SSLExpiryEntry {
    let names = [
      "renewal.example.com", "billing.example.net", "status.example.org",
      "api.billing.staging.very-long-subdomain.example.com", "portal.example.net",
      "health.example.org",
    ]
    let days = [15.0, 15, 49, 120, 220, 300]
    let domains = names.map { WatchedDomain(hostname: $0, addedAt: date) }
    let snapshots = zip(domains, days).map { domain, remaining in
      snapshot(for: domain, at: date, days: remaining)
    }
    return SSLExpiryEntry(
      date: date, domains: domains, snapshots: snapshots,
      errorMessage: nil, reminderErrorMessage: nil, selection: .automatic)
  }

  private static func stressFixture(at date: Date) -> SSLExpiryEntry {
    let names = [
      "expired.example.net", "api.payment.production.very-long-subdomain.example.com",
      "untrusted.example.org", "critical.example.net", "unchecked.example.com",
      "healthy.example.org",
    ]
    let domains = names.map { WatchedDomain(hostname: $0, addedAt: date) }
    let snapshots = [
      snapshot(for: domains[0], at: date, days: -2),
      snapshot(
        for: domains[1], at: date, days: 8, state: .failed,
        detail: "连接超时，暂时无法读取新证书", failures: 3),
      snapshot(for: domains[2], at: date, days: 30, state: .untrusted),
      snapshot(for: domains[3], at: date, days: 1),
      snapshot(for: domains[5], at: date, days: 250),
    ]
    return SSLExpiryEntry(
      date: date, domains: domains, snapshots: snapshots,
      errorMessage: nil, reminderErrorMessage: nil, selection: .automatic)
  }

  private static func overflowFixture(
    from normal: SSLExpiryEntry, at date: Date
  ) -> SSLExpiryEntry {
    let extras = ["reports.example.com", "cdn.example.net", "mail.example.org"]
      .map { WatchedDomain(hostname: $0, addedAt: date) }
    let added = zip(extras, [330.0, 390, 480]).enumerated().map { index, pair in
      snapshot(
        for: pair.0, at: date, days: pair.1,
        checkedAgo: index == 0 ? 2 * 86_400 : 3_600)
    }
    return SSLExpiryEntry(
      date: date, domains: normal.domains + extras, snapshots: normal.snapshots + added,
      errorMessage: nil, reminderErrorMessage: nil, selection: .automatic)
  }

  private static func snapshot(
    for domain: WatchedDomain, at date: Date, days: Double,
    state: CertificateCheckState = .trusted, detail: String? = nil, failures: Int = 0,
    checkedAgo: TimeInterval = 3_600
  ) -> CertificateSnapshot {
    let checkedAt = date.addingTimeInterval(-checkedAgo)
    return CertificateSnapshot(
      hostname: domain.hostname, checkedAt: checkedAt,
      expiresAt: date.addingTimeInterval(days * 86_400), checkState: state,
      detail: detail,
      lastSuccessfulCheckAt: state == .failed ? date.addingTimeInterval(-7 * 86_400) : checkedAt,
      consecutiveFailureCount: failures, port: domain.port,
      validFrom: date.addingTimeInterval(-75 * 86_400))
  }
}
