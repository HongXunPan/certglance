import Foundation
import UserNotifications
import WidgetKit

@MainActor
final class DashboardModel: ObservableObject {
  @Published var input = ""
  @Published var inputError: String?
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
      let endpoint = try DomainInput.parseEndpoint(input)
      let domain = WatchedDomain(
        hostname: endpoint.hostname, port: endpoint.port, addedAt: Date())
      guard !domains.contains(where: { $0.id == domain.id }) else {
        throw DomainInputError.duplicate
      }
      let updated = domains + [domain]
      try store.replaceDomains(updated)
      domains = updated
      input = ""
      inputError = nil
      WidgetCenter.shared.reloadTimelines(ofKind: CertGlanceIdentity.widgetKind)
      await refresh()
    } catch {
      if error is DomainInputError {
        inputError = error.localizedDescription
      } else {
        alertMessage = error.localizedDescription
      }
    }
  }

  func removeDomain(_ id: String) async {
    guard let store else { return }
    do {
      let updated = domains.filter { $0.id != id }
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
        let queue = DomainCheckQueue.ordered(
          domains, snapshots: try store.snapshots(), at: .now)
        _ = try await refresher.refresh(queue, store: store)
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

  func snapshot(for id: String) -> CertificateSnapshot? {
    snapshots.first { $0.id == id }
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
