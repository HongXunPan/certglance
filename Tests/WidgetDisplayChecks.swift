import Foundation

@main
struct WidgetDisplayChecks {
  static func main() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let domains = (1...7).map {
      WatchedDomain(hostname: "domain\($0).example", addedAt: now)
    }
    let second = CertificateSnapshot(
      hostname: domains[1].hostname, checkedAt: now,
      expiresAt: now.addingTimeInterval(4 * 86_400), checkState: .trusted, detail: nil)
    let first = CertificateSnapshot(
      hostname: domains[0].hostname, checkedAt: now,
      expiresAt: now.addingTimeInterval(80 * 86_400), checkState: .trusted, detail: nil)
    let snapshots = [first, second]
    let ordered = DashboardOrder.sorted(domains, snapshots: snapshots, at: now)

    expect(
      WidgetDisplaySelection.automatic.resolve(in: ordered)?.id == domains[1].id,
      "自动组件应按现有风险排序选择端点")
    expect(
      WidgetDisplaySelection.pinned(domains[0].id).resolve(in: ordered)?.id == domains[0].id,
      "固定组件不应受风险排序影响")
    expect(
      WidgetDisplaySelection.pinned(nil).resolve(in: ordered) == nil,
      "尚未配置的固定组件不应自动展示其他端点")
    expect(
      WidgetDisplaySelection.pinned("removed.example").resolve(in: ordered) == nil,
      "已移除的固定端点不应静默替换")
    expect(
      WidgetOverview.attentionCount(domains: domains, snapshots: snapshots, at: now) == 6,
      "需处理数量应包含待检查和到期风险，不包含健康端点")
    let counts = WidgetOverview.severityCounts(
      domains: domains, snapshots: snapshots, at: now)
    expect(
      counts[.soon] == 1 && counts[.healthy] == 1 && counts[.unchecked] == 5,
      "大号分类数量应与端点状态一致")
    let items = CertificateDisplayGrouping.items(domains, snapshots: snapshots, at: now)
    expect(
      WidgetOverview.hiddenCount(
        total: domains.count, items: items, visibleLimit: WidgetOverview.mediumVisibleLimit) == 4,
      "中号应显示三个风险项，并报告剩余端点")
    expect(
      WidgetOverview.hiddenCount(
        total: domains.count, items: items, visibleLimit: WidgetOverview.largeVisibleLimit) == 1,
      "大号应显示六个风险项，并报告剩余端点")
    expect(
      WidgetOverview.hiddenCount(total: 2, items: Array(items.prefix(2)), visibleLimit: 6) == 0,
      "端点不足上限时不应出现负数")
    let third = CertificateSnapshot(
      hostname: domains[2].hostname, checkedAt: now,
      expiresAt: second.expiresAt, checkState: .trusted, detail: nil)
    let groupedItems = CertificateDisplayGrouping.items(
      domains, snapshots: snapshots + [third], at: now)
    expect(groupedItems.first?.domains.count == 2, "同日组应占一个展示项")
    expect(
      WidgetOverview.hiddenCount(
        total: domains.count, items: groupedItems,
        visibleLimit: WidgetOverview.mediumVisibleLimit) == 3,
      "隐藏数量应扣除同日组内已展示的全部端点")

    print("Widget 展示规则通过")
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
