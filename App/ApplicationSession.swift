import AppKit
import Combine
import Foundation

@MainActor
final class ApplicationSession: ObservableObject {
  let certificates = DashboardModel()
  let registrations = RegistrationDashboardModel()
  private let activity = NSBackgroundActivityScheduler(
    identifier: "com.HongXunPan.CertGlance.periodic-check")
  private var started = false
  private var work: Task<Void, Never>?

  func start() {
    guard !started else { return }
    started = true
    activity.repeats = true
    activity.interval = RegistrationPlanning.activityInterval
    activity.tolerance = 15 * 60
    activity.qualityOfService = .background
    activity.schedule { [weak self] completion in
      Task { @MainActor in
        await self?.checkDue()
        completion(.finished)
      }
    }
    // 任务由 App 级对象持有，不随窗口视图的 task 取消。
    work = Task {
      await certificates.load()
      guard !Task.isCancelled else {
        work = nil
        return
      }
      await registrations.load()
      work = nil
    }
  }

  func checkDue() async {
    guard started, work == nil else { return }
    let task = Task {
      await certificates.refreshDue()
      guard !Task.isCancelled else { return }
      await registrations.refresh()
    }
    work = task
    await task.value
    work = nil
  }

  func stop() {
    started = false
    activity.invalidate()
    work?.cancel()
    work = nil
  }
}

@MainActor
final class ApplicationLifecycleDelegate: NSObject, NSApplicationDelegate {
  let session = ApplicationSession()

  func applicationDidFinishLaunching(_ notification: Notification) { session.start() }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

  func applicationWillTerminate(_ notification: Notification) { session.stop() }
}
