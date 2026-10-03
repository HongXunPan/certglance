import Foundation

@main
struct WidgetPlanningChecks {
  static func main() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let domains = (1...10).map {
      WatchedDomain(hostname: "domain\($0).example", addedAt: now)
    }
    let selected = WidgetPlanning.domainsNeedingCheck(domains, snapshots: [], at: now)
    expect(selected.count == 10, "未检查域名都应进入候选队列")
    expect(
      Array(selected.prefix(WidgetPlanning.maximumChecksPerTimeline)).count == 6,
      "单次时间线最多检查六个域名")

    let expiry = now.addingTimeInterval(6 * 86_400 + 3_600)
    let snapshot = CertificateSnapshot(
      hostname: domains[0].hostname, checkedAt: now,
      expiresAt: expiry, checkState: .trusted, detail: nil)
    let dates = WidgetPlanning.timelineDates(snapshots: [snapshot], from: now)
    expect(dates.first == now, "首个时间线条目应立即显示")
    expect(dates.count >= 7, "后续天数变化应预排时间线")
    expect(
      dates.allSatisfy { $0 <= now.addingTimeInterval(7 * 86_400) },
      "预排时间不能超出窗口")
    expect(
      zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 300 },
      "相邻条目至少间隔五分钟")
    expect(
      snapshot.daysRemaining(at: dates[1]) == 6,
      "时间线更新后剩余天数应与证书截止时间一致")
    let sameExpiry = CertificateSnapshot(
      hostname: domains[1].hostname, checkedAt: now,
      expiresAt: expiry, checkState: .trusted, detail: nil)
    expect(
      WidgetPlanning.timelineDates(snapshots: [snapshot, sameExpiry], from: now).count
        == dates.count,
      "相同变化时刻不能重复生成时间线条目")
    expect(
      WidgetPlanning.timelineDates(snapshots: [snapshot], from: now, maximumEntries: 3).count
        == 3,
      "时间线条目应有总量上限")

    let checked = CertificateSnapshot(
      hostname: domains[0].hostname, checkedAt: now,
      expiresAt: expiry, checkState: .trusted, detail: nil)
    let pending = WidgetPlanning.domainsNeedingCheck(
      domains, snapshots: [checked], at: now.addingTimeInterval(3_600))
    expect(pending.count == 9, "新快照不应在短时间内重复检查")
    expect(
      !pending.contains(where: { $0.hostname == domains[0].hostname }),
      "已检查域名不应挤占未检查域名的批次")
    let stale = WidgetPlanning.domainsNeedingCheck(
      [domains[0]], snapshots: [checked],
      at: now.addingTimeInterval(WidgetPlanning.staleInterval))
    expect(stale.count == 1, "超过检查间隔的域名应重新进入队列")
    print("Widget 时间线与分批检查规则通过")
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
