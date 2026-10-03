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
  @Published private(set) var notificationDenied = false
  @Published private(set) var storageError: String?
  @Published private(set) var lastActionMessage: String?
  @Published var alertMessage: String?

  private let store: (any SnapshotStore)?
  private let refresher = DashboardRefresher()
  private let notifications = NotificationCoordinator()
  private var pendingRefreshes: [DashboardRefreshSelection] = []

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
      storageError = nil
    } catch {
      domains = []
      snapshots = []
      storageError = error.localizedDescription
      return
    }
    await updateNotificationDescription()
    await enqueueRefresh(.due)
  }

  func addDomain() async -> Bool {
    guard let store, storageError == nil else {
      inputError = storageError ?? "共享数据不可用。"
      return false
    }
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
      lastActionMessage = "已添加 \(domain.displayName)；检查结果会显示在看板中。"
      WidgetCenter.shared.reloadTimelines(ofKind: CertGlanceIdentity.widgetKind)
      Task { await enqueueRefresh(.endpoint(domain.id)) }
      return true
    } catch {
      inputError = error.localizedDescription
      if error is SharedStoreError { storageError = error.localizedDescription }
      return false
    }
  }

  func removeDomain(_ id: String) async {
    guard let store, storageError == nil else { return }
    do {
      let updated = domains.filter { $0.id != id }
      try store.replaceDomains(updated)
      let remaining = try store.snapshots()
      domains = updated
      snapshots = remaining
      lastActionMessage = nil
      WidgetCenter.shared.reloadTimelines(ofKind: CertGlanceIdentity.widgetKind)
    } catch {
      alertMessage = error.localizedDescription
      if error is SharedStoreError { storageError = error.localizedDescription }
      return
    }
    await synchronizeNotifications(store: store)
  }

  func refresh() async {
    await enqueueRefresh(.all)
  }

  func dismissActionMessage() {
    lastActionMessage = nil
  }

  private func enqueueRefresh(_ scope: DashboardRefreshSelection) async {
    guard let store, storageError == nil else { return }
    pendingRefreshes.append(scope)
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    while !pendingRefreshes.isEmpty, storageError == nil {
      let next = pendingRefreshes.removeFirst()
      await performRefresh(next, store: store)
    }
    pendingRefreshes.removeAll()
  }

  private func performRefresh(_ scope: DashboardRefreshSelection, store: any SnapshotStore) async {
    do {
      let currentDomains = try store.domains()
      let currentSnapshots = try store.snapshots()
      let queue = scope.ordered(currentDomains, snapshots: currentSnapshots, at: .now)
      if !queue.isEmpty {
        _ = try await refresher.refresh(queue, store: store)
      }
      domains = try store.domains()
      snapshots = try store.snapshots()
      if !queue.isEmpty {
        WidgetCenter.shared.reloadTimelines(ofKind: CertGlanceIdentity.widgetKind)
      }
    } catch {
      alertMessage = "证书检查未完成：\(error.localizedDescription)"
      if error is SharedStoreError { storageError = error.localizedDescription }
      return
    }
    await synchronizeNotifications(store: store)
  }

  private func synchronizeNotifications(store: any SnapshotStore) async {
    do {
      try await notifications.synchronize(store: store)
    } catch {
      alertMessage = "证书数据已保留，但提醒同步失败：\(error.localizedDescription)"
    }
  }

  func requestNotifications() async {
    guard let store, storageError == nil else { return }
    if notificationDenied {
      await updateNotificationDescription()
      if notificationsEnabled {
        await synchronizeNotifications(store: store)
        return
      }
      alertMessage = "请前往“系统设置 → 通知 → CertGlance”开启通知；返回应用后再次点击“检查通知状态”。"
      return
    }
    do {
      let granted = try await notifications.requestAuthorization()
      await updateNotificationDescription()
      if granted {
        await synchronizeNotifications(store: store)
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
      notificationDenied = false
    case .denied:
      notificationDescription = "通知已关闭，请在系统设置中开启"
      notificationsEnabled = false
      notificationDenied = true
    default:
      notificationDescription = "尚未授权通知"
      notificationsEnabled = false
      notificationDenied = false
    }
  }
}
