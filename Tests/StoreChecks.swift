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
    let trusted = CertificateSnapshot(
      hostname: first.hostname, checkedAt: now, expiresAt: expiry,
      checkState: .trusted, detail: nil)
    let other = CertificateSnapshot(
      hostname: second.hostname, checkedAt: now,
      expiresAt: now.addingTimeInterval(60 * 86_400), checkState: .trusted, detail: nil)
    let initial = try store.mergeSnapshots([trusted, other])
    expect(initial.count == 2, "证书快照应合并写入")

    let failed = CertificateSnapshot(
      hostname: first.hostname, checkedAt: now.addingTimeInterval(10),
      expiresAt: nil, checkState: .failed, detail: "连接超时")
    let afterFailure = try store.mergeSnapshots([failed])
    expect(afterFailure.first?.checkState == .failed, "失败不能被旧成功状态覆盖")
    expect(afterFailure.first?.expiresAt == expiry, "失败应保留已知截止时间")
    let afterOlderResult = try store.mergeSnapshots([trusted])
    expect(afterOlderResult.first?.checkState == .failed, "较旧的检查结果不得覆盖新结果")

    try store.addNotificationTokens(["first-30"])
    try store.addNotificationTokens(["second-7"])
    expect(try store.notificationTokens() == ["first-30", "second-7"], "提醒标记应并集写入")

    try store.replaceDomains([second])
    expect(try store.snapshots().map(\.hostname) == [second.hostname], "移除域名应清理对应快照")
    try store.replaceDomains([first, second])
    expect(try store.snapshots().map(\.hostname) == [second.hostname], "重新添加不得复活旧快照")

    let snapshotFile = root.appendingPathComponent("state/snapshots.v1.json")
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
}
