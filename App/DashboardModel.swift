import Foundation
import UserNotifications
import WidgetKit

@MainActor
final class DashboardModel: ObservableObject {
  @Published var input = ""
  @Published private(set) var domains: [WatchedDomain] = []
  @Published private(set) var snapshots: [CertificateSnapshot] = []
  @Published private(set) var isChecking = false
  @Published private(set) var notificationDescription = "正在读取通知状态"
  @Published private(set) var notificationsEnabled = false
  @Published var alertMessage: String?
  let storageError: String?

  private let store: (any SnapshotStore)?
  private let refresher = DashboardRefresher()
  private let notifications = NotificationCoordinator()
  private var refreshRequested = false

  init() {
    do {
      store = try FileSnapshotStore(createIfNeeded: true)
      storageError = nil
    } catch {
      store = nil
      storageError = error.localizedDescription
    }
  }

  func load() async {
    guard let store else { return }
    do {
      domains = try store.domains()
      snapshots = try store.snapshots()
    } catch {
      alertMessage = error.localizedDescription
      return
    }
    await updateNotificationDescription()
    if !domains.isEmpty { await refresh() }
  }

  func addDomain() async {
    guard let store else { return }
    do {
      let hostname = try DomainInput.normalize(input)
      guard !domains.contains(where: { $0.hostname == hostname }) else {
        throw DomainInputError.duplicate
      }
      let updated = domains + [WatchedDomain(hostname: hostname, addedAt: Date())]
      try store.replaceDomains(updated)
      domains = updated
      input = ""
      WidgetCenter.shared.reloadTimelines(ofKind: CertGlanceIdentity.widgetKind)
      await refresh()
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  func removeDomain(_ hostname: String) async {
    guard let store else { return }
    do {
      let updated = domains.filter { $0.hostname != hostname }
      try store.replaceDomains(updated)
      let remaining = try store.snapshots()
      domains = updated
      snapshots = remaining
      WidgetCenter.shared.reloadTimelines(ofKind: CertGlanceIdentity.widgetKind)
      try await notifications.synchronize(store: store)
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  func refresh() async {
    guard let store else { return }
    if isChecking {
      refreshRequested = true
      return
    }
    isChecking = true
    defer { isChecking = false }
    repeat {
      refreshRequested = false
      do {
        _ = try await refresher.refresh(domains, store: store)
        snapshots = try store.snapshots()
        WidgetCenter.shared.reloadTimelines(ofKind: CertGlanceIdentity.widgetKind)
        try await notifications.synchronize(store: store)
      } catch {
        alertMessage = "检查或提醒未完成：\(error.localizedDescription)"
      }
    } while refreshRequested
  }

  func requestNotifications() async {
    guard let store else { return }
    do {
      let granted = try await notifications.requestAuthorization()
      await updateNotificationDescription()
      if granted {
        try await notifications.synchronize(store: store)
      } else {
        alertMessage = "未获得通知权限；可在系统设置中重新开启。"
      }
    } catch {
      alertMessage = error.localizedDescription
    }
  }

  func snapshot(for hostname: String) -> CertificateSnapshot? {
    snapshots.first { $0.hostname == hostname }
  }

  private func updateNotificationDescription() async {
    let status = await notifications.authorizationStatus()
    switch status {
    case .authorized, .provisional:
      notificationDescription = "通知已开启"
      notificationsEnabled = true
    case .denied:
      notificationDescription = "通知已关闭，请在系统设置中开启"
      notificationsEnabled = false
    default:
      notificationDescription = "尚未授权通知"
      notificationsEnabled = false
    }
  }
}
