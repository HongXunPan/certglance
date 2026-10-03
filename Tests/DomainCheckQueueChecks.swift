import Foundation

@main
struct DomainCheckQueueChecks {
  static func main() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let domains = (1...10).map {
      WatchedDomain(hostname: "domain\($0).example", addedAt: now)
    }
    let firstBatch = DomainCheckQueue.due(domains, snapshots: [], at: now)
    expect(firstBatch.count == 10, "未检查域名都应进入候选队列")
    expect(
      Array(firstBatch.prefix(WidgetPlanning.maximumChecksPerTimeline)).count == 6,
      "单次时间线最多检查六个域名")

    let checked = domains.prefix(6).map {
      snapshot($0.hostname, checkedAt: now, expiresAt: now.addingTimeInterval(60 * 86_400))
    }
    let pending = DomainCheckQueue.due(
      domains, snapshots: checked, at: now.addingTimeInterval(3_600))
    expect(pending.count == 4, "已检查域名不应挤占未检查域名的批次")
    expect(
      pending.allSatisfy { !domains.prefix(6).contains($0) },
      "未检查域名应在下一批优先派发")
    let stale = DomainCheckQueue.due(
      [domains[0]], snapshots: [checked[0]],
      at: now.addingTimeInterval(DomainCheckQueue.minimumCheckInterval))
    expect(stale.count == 1, "满十二小时后应重新进入队列")

    let recent = now.addingTimeInterval(-13 * 3_600)
    let overdue = now.addingTimeInterval(-25 * 3_600)
    let urgent = snapshot(
      "urgent.example", checkedAt: recent, expiresAt: now.addingTimeInterval(3_600))
    let healthy = snapshot(
      "healthy.example", checkedAt: overdue, expiresAt: now.addingTimeInterval(60 * 86_400))
    let fairness = DomainCheckQueue.due(
      [domain("urgent.example", now), domain("healthy.example", now)],
      snapshots: [urgent, healthy], at: now)
    expect(fairness.first?.hostname == "healthy.example", "超期未检查域名应优先，避免饥饿")
    let firstTime = DomainCheckQueue.due(
      [domain("healthy.example", now), domain("first.example", now)],
      snapshots: [healthy], at: now)
    expect(firstTime.first?.hostname == "first.example", "从未检查的域名应先进入队列")

    let expiryOrder = DomainCheckQueue.due(
      [domain("healthy.example", now), domain("urgent.example", now)],
      snapshots: [
        snapshot(
          "healthy.example", checkedAt: recent, expiresAt: now.addingTimeInterval(60 * 86_400)),
        urgent,
      ], at: now)
    expect(expiryOrder.first?.hostname == "urgent.example", "同档位证书临期应有更高权重")

    let trusted = snapshot(
      "trusted.example", checkedAt: recent, expiresAt: now.addingTimeInterval(60 * 86_400))
    let untrusted = snapshot(
      "untrusted.example", checkedAt: recent,
      expiresAt: now.addingTimeInterval(60 * 86_400), state: .untrusted)
    let trustOrder = DomainCheckQueue.due(
      [domain("trusted.example", now), domain("untrusted.example", now)],
      snapshots: [trusted, untrusted], at: now)
    expect(trustOrder.first?.hostname == "untrusted.example", "证书不受信任应提高权重")

    let once = snapshot(
      "a.example", checkedAt: recent, expiresAt: nil, state: .failed, failures: 1)
    let twice = snapshot(
      "z.example", checkedAt: recent, expiresAt: nil, state: .failed, failures: 2)
    let failureOrder = DomainCheckQueue.due(
      [domain("a.example", now), domain("z.example", now)],
      snapshots: [once, twice], at: now)
    expect(failureOrder.first?.hostname == "z.example", "第二次连续失败应提高权重")
    let cappedTwice = snapshot(
      "a.example", checkedAt: recent, expiresAt: nil, state: .failed, failures: 2)
    let many = snapshot(
      "z.example", checkedAt: recent, expiresAt: nil, state: .failed, failures: 99)
    let capped = DomainCheckQueue.due(
      [domain("z.example", now), domain("a.example", now)],
      snapshots: [many, cappedTwice], at: now)
    expect(capped.map(\.hostname) == ["a.example", "z.example"], "两次以后失败权重不得继续增长")

    let oldSuccess = snapshot(
      "old.example", checkedAt: recent, expiresAt: nil,
      lastSuccess: now.addingTimeInterval(-8 * 86_400))
    let recentSuccess = snapshot("new.example", checkedAt: recent, expiresAt: nil)
    let successOrder = DomainCheckQueue.due(
      [domain("new.example", now), domain("old.example", now)],
      snapshots: [recentSuccess, oldSuccess], at: now)
    expect(successOrder.first?.hostname == "old.example", "较久未成功读取应有更高权重")
    let sevenDays = snapshot(
      "a.example", checkedAt: recent, expiresAt: nil,
      lastSuccess: now.addingTimeInterval(-7 * 86_400))
    let hundredDays = snapshot(
      "z.example", checkedAt: recent, expiresAt: nil,
      lastSuccess: now.addingTimeInterval(-100 * 86_400))
    let cappedSuccess = DomainCheckQueue.due(
      [domain("z.example", now), domain("a.example", now)],
      snapshots: [hundredDays, sevenDays], at: now)
    expect(cappedSuccess.map(\.hostname) == ["a.example", "z.example"], "成功时间权重不得无限增长")
    let customPort = WatchedDomain(hostname: "same.example", port: 8443, addedAt: now)
    let defaultPort = WatchedDomain(hostname: "same.example", addedAt: now)
    let defaultSnapshot = snapshot(
      "same.example", checkedAt: now, expiresAt: now.addingTimeInterval(60 * 86_400))
    let separate = DomainCheckQueue.due(
      [defaultPort, customPort], snapshots: [defaultSnapshot], at: now)
    expect(separate.map(\.id) == [customPort.id], "同域名不同端口应独立参与检查队列")
    print("多域名检查队列规则通过")
  }

  private static func domain(_ hostname: String, _ addedAt: Date) -> WatchedDomain {
    WatchedDomain(hostname: hostname, addedAt: addedAt)
  }

  private static func snapshot(
    _ hostname: String, checkedAt: Date, expiresAt: Date?,
    state: CertificateCheckState = .trusted, failures: Int = 0,
    lastSuccess: Date? = nil
  ) -> CertificateSnapshot {
    CertificateSnapshot(
      hostname: hostname, checkedAt: checkedAt, expiresAt: expiresAt,
      checkState: state, detail: nil, lastSuccessfulCheckAt: lastSuccess,
      consecutiveFailureCount: failures)
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
