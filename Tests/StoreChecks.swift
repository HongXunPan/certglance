import Foundation

@main
struct StoreChecks {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      fatalError("请传入父仓受管临时目录")
    }
    let parent = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let root = parent.appendingPathComponent(
      "certglance-store-check-20261003-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    expect(
      (try? FileSnapshotStore(directoryURL: root, createIfNeeded: false)) == nil,
      "Widget 在宿主首次启动前不得自行创建共享目录")

    let store = try FileSnapshotStore(directoryURL: root, createIfNeeded: true)
    let widgetStore = try FileSnapshotStore(directoryURL: root, createIfNeeded: false)
    let now = Date(timeIntervalSince1970: 1_000_000)
    let first = WatchedDomain(hostname: "first.example", addedAt: now)
    let second = WatchedDomain(hostname: "second.example", addedAt: now)
    try store.replaceDomains([first, second])
    expect(try store.domains().count == 2, "域名写入后应可读")
    expect(try widgetStore.domains().count == 2, "Widget 应可只读配置")

    let expiry = now.addingTimeInterval(5 * 86_400)
    let validFrom = now.addingTimeInterval(-85 * 86_400)
    let trusted = CertificateSnapshot(
      hostname: first.hostname, checkedAt: now, expiresAt: expiry,
      checkState: .trusted, detail: nil, validFrom: validFrom)
    let other = CertificateSnapshot(
      hostname: second.hostname, checkedAt: now,
      expiresAt: now.addingTimeInterval(60 * 86_400), checkState: .trusted, detail: nil)
    let initial = try store.mergeSnapshots([trusted, other])
    expect(initial.count == 2, "证书快照应合并写入")
    expect(
      initial.first?.lastSuccessfulCheckAt == now && initial.first?.consecutiveFailureCount == 0,
      "成功读取证书应记录成功时间并清零连续失败")

    let failed = CertificateSnapshot(
      hostname: first.hostname, checkedAt: now.addingTimeInterval(10),
      expiresAt: nil, checkState: .failed, detail: "连接超时")
    let afterFailure = try store.mergeSnapshots([failed])
    expect(afterFailure.first?.checkState == .failed, "失败不能被旧成功状态覆盖")
    expect(afterFailure.first?.expiresAt == expiry, "失败应保留已知截止时间")
    expect(afterFailure.first?.validFrom == validFrom, "失败应保留同一证书的有效期起点")
    expect(
      afterFailure.first?.lastSuccessfulCheckAt == now
        && afterFailure.first?.consecutiveFailureCount == 1,
      "失败应保留最近成功时间并累计一次")
    let afterDuplicate = try store.mergeSnapshots([failed])
    expect(afterDuplicate.first?.consecutiveFailureCount == 1, "重复合并同一失败不得重复计数")
    let failedAgain = CertificateSnapshot(
      hostname: first.hostname, checkedAt: now.addingTimeInterval(20),
      expiresAt: nil, checkState: .failed, detail: "连接超时")
    let afterSecondFailure = try store.mergeSnapshots([failedAgain])
    expect(afterSecondFailure.first?.consecutiveFailureCount == 2, "连续失败应累积")
    let untrusted = CertificateSnapshot(
      hostname: first.hostname, checkedAt: now.addingTimeInterval(30),
      expiresAt: expiry, checkState: .untrusted, detail: "证书不受信任",
      validFrom: validFrom.addingTimeInterval(10))
    let afterObserved = try store.mergeSnapshots([untrusted])
    expect(
      afterObserved.first?.lastSuccessfulCheckAt == untrusted.checkedAt
        && afterObserved.first?.consecutiveFailureCount == 0,
      "读取到不受信任证书仍应视为探测成功并清零失败")
    expect(
      afterObserved.first?.validFrom == untrusted.validFrom,
      "新证书应替换有效期起点，不能与旧快照拼接")
    let afterOlderResult = try store.mergeSnapshots([trusted])
    expect(afterOlderResult.first?.checkState == .untrusted, "较旧的检查结果不得覆盖新结果")

    try store.addNotificationTokens(["first-30"])
    try store.addNotificationTokens(["second-7"])
    expect(try store.notificationTokens() == ["first-30", "second-7"], "提醒标记应并集写入")

    try store.replaceDomains([second])
    expect(try store.snapshots().map(\.hostname) == [second.hostname], "移除域名应清理对应快照")
    try store.replaceDomains([first, second])
    expect(try store.snapshots().map(\.hostname) == [second.hostname], "重新添加不得复活旧快照")

    let snapshotFile = root.appendingPathComponent("state/snapshots.v1.json")
    let legacy = LegacySnapshot(
      hostname: first.hostname, checkedAt: now, expiresAt: expiry,
      checkState: .trusted, detail: nil)
    try JSONEncoder().encode([legacy]).write(to: snapshotFile, options: .atomic)
    let migrated = try store.snapshots()
    expect(
      migrated.first?.lastSuccessfulCheckAt == now
        && migrated.first?.consecutiveFailureCount == 0 && migrated.first?.port == 443
        && migrated.first?.validFrom == nil,
      "旧版快照应推断成功时间并补齐失败次数")
    let alternate = WatchedDomain(hostname: first.hostname, port: 8443, addedAt: now)
    try store.replaceDomains([first, alternate, second])
    let alternateSnapshot = CertificateSnapshot(
      hostname: first.hostname, checkedAt: now.addingTimeInterval(100), expiresAt: expiry,
      checkState: .trusted, detail: nil, port: 8443)
    let independent = try store.mergeSnapshots([alternateSnapshot])
    expect(independent.contains { $0.id == alternate.id }, "同域名不同端口应独立存储")
    expect(independent.contains { $0.id == first.id }, "自定义端口不得覆盖默认端口")
    try store.replaceDomains([first, second])
    expect(try store.snapshots().allSatisfy { $0.port == 443 }, "移除自定义端口只清理该端点")
    let original = root.appendingPathComponent("state/snapshots-original.json")
    try FileManager.default.moveItem(at: snapshotFile, to: original)
    try FileManager.default.createSymbolicLink(at: snapshotFile, withDestinationURL: original)
    expect((try? store.snapshots()) == nil, "共享文件链接不能被当作正常数据")
    try FileManager.default.removeItem(at: snapshotFile)
    try FileManager.default.moveItem(at: original, to: snapshotFile)

    let config = root.appendingPathComponent("config/domains.v1.json")
    try Data("无效数据".utf8).write(to: config, options: .atomic)
    expect((try? store.domains()) == nil, "损坏的数据不能静默当作空列表")
    expect(try Data(contentsOf: config) == Data("无效数据".utf8), "损坏数据必须留存以便恢复")
    print("文件共享仓储定点检查通过")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }

  private struct LegacySnapshot: Encodable {
    let hostname: String
    let checkedAt: Date
    let expiresAt: Date?
    let checkState: CertificateCheckState
    let detail: String?
  }
}
