import Foundation

@main
struct WidgetRefreshLeaseChecks {
  static func main() throws {
    guard CommandLine.arguments.count == 2 else {
      fatalError("需要受管临时目录")
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let store = try FileSnapshotStore(directoryURL: directory, createIfNeeded: true)
    try verifyMutualExclusion(store: store)
    let now = Date(timeIntervalSince1970: 1_000_000)
    do {
      let afterRelease = try store.tryAcquireWidgetRefreshLease()
      precondition(afterRelease != nil, "释放后应可再次领取")
      let started = try afterRelease?.beginBatch(at: now, minimumSpacing: 3_600)
      precondition(started == true, "首批检查应可启动")
      withExtendedLifetime(afterRelease) {}
    }
    do {
      let withinHour = try store.tryAcquireWidgetRefreshLease()
      let started = try withinHour?.beginBatch(
        at: now.addingTimeInterval(600), minimumSpacing: 3_600)
      precondition(started == false, "同一小时内不应启动第二批")
      withExtendedLifetime(withinHour) {}
    }
    do {
      let nextHour = try store.tryAcquireWidgetRefreshLease()
      let started = try nextHour?.beginBatch(
        at: now.addingTimeInterval(3_600), minimumSpacing: 3_600)
      precondition(started == true, "间隔达到一小时后应允许续批")
      withExtendedLifetime(nextHour) {}
    }
    print("Widget 自动检查排他锁通过")
  }

  private static func verifyMutualExclusion(store: FileSnapshotStore) throws {
    let first = try store.tryAcquireWidgetRefreshLease()
    precondition(first != nil, "首个组件应可领取检查")
    let competing = try store.tryAcquireWidgetRefreshLease()
    precondition(competing == nil, "其他组件不应重复领取")
    withExtendedLifetime(first) {}
  }
}
