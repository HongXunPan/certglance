import Foundation
import UserNotifications
import WidgetKit

@MainActor
final class RegistrationDashboardModel: ObservableObject {
  @Published var input = ""
  @Published var inputError: String?
  @Published private(set) var domains: [RegisteredDomain] = []
  @Published private(set) var snapshots: [RegistrationSnapshot] = []
  @Published private(set) var isChecking = false
  @Published private(set) var storageError: String?
  @Published var actionError: String?

  private let store: (any RegistrationStore)?
  private let checker = RegistrationChecker()

  init() {
    do {
      store = try FileSnapshotStore(createIfNeeded: true)
    } catch {
      store = nil
      storageError = error.localizedDescription
    }
  }

  func load() async {
    reload()
    await refresh()
  }

  func reload() {
    guard let store else { return }
    do {
      let currentDomains = try store.registeredDomains()
      let currentSnapshots = try store.registrationSnapshots()
      domains = currentDomains
      snapshots = currentSnapshots
      storageError = nil
    } catch {
      storageError = error.localizedDescription
    }
  }

  func add() async -> Bool {
    guard let store, storageError == nil else { return false }
    do {
      let hostname = try RegistrationInput.parse(input)
      let current = try store.registeredDomains()
      guard !current.contains(where: { $0.hostname == hostname }) else {
        throw RegistrationLookupError.message("这个注册域名已经在列表中。")
      }
      try store.replaceRegisteredDomains(
        current + [RegisteredDomain(hostname: hostname, addedAt: .now)])
      input = ""
      inputError = nil
      reload()
      reloadWidget()
      Task { await refresh(only: hostname) }
      return true
    } catch {
      inputError = error.localizedDescription
      if error is SharedStoreError { storageError = error.localizedDescription }
      return false
    }
  }

  func remove(_ id: String) async {
    guard let store, storageError == nil else { return }
    do {
      try store.replaceRegisteredDomains(try store.registeredDomains().filter { $0.id != id })
      reload()
      reloadWidget()
    } catch {
      actionError = error.localizedDescription
      if error is SharedStoreError { storageError = error.localizedDescription }
      return
    }
    await synchronizeNotifications(store)
  }

  func refresh(force: Bool = false, only hostname: String? = nil) async {
    guard let store, storageError == nil, !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    do {
      let current = try store.registeredDomains()
      let saved = try store.registrationSnapshots()
      let selected = hostname.map { host in current.filter { $0.hostname == host } } ?? current
      let queue = RegistrationPlanning.due(selected, snapshots: saved, at: .now, force: force)
      if force { await checker.resetDiscovery() }
      for domain in queue {
        try Task.checkCancellation()
        let result = await checker.check(domain)
        try Task.checkCancellation()
        try store.mergeRegistrationSnapshots([result])
        reload()
        reloadWidget()
      }
    } catch is CancellationError {
      return
    } catch {
      actionError = "注册查询未完成：\(error.localizedDescription)"
      if error is SharedStoreError { storageError = error.localizedDescription }
      return
    }
    await synchronizeNotifications(store)
  }

  func snapshot(for id: String) -> RegistrationSnapshot? { snapshots.first { $0.id == id } }

  func requestNotifications() async {
    guard let store else { return }
    do {
      let coordinator = NotificationCoordinator()
      let status = await coordinator.authorizationStatus()
      guard status != .denied else {
        actionError = "请前往“系统设置 → 通知 → CertGlance”开启通知，返回后再次检查。"
        return
      }
      let granted = try await coordinator.requestAuthorization()
      guard granted else { return }
      // 注册提醒不依赖证书配置可读，避免另一类数据损坏阻止当前功能授权。
      try await RegistrationNotifications().synchronize(store: store)
      if (try? store.domains()) != nil {
        try await coordinator.synchronize(store: store)
      }
    } catch {
      actionError = "通知授权或提醒同步未完成：\(error.localizedDescription)"
    }
  }

  private func synchronizeNotifications(_ store: any RegistrationStore) async {
    do {
      try await RegistrationNotifications().synchronize(store: store)
    } catch {
      actionError = "注册数据已保留，但提醒同步失败：\(error.localizedDescription)"
    }
  }

  private func reloadWidget() {
    WidgetCenter.shared.reloadTimelines(ofKind: RegistrationWidgetIdentity.kind)
  }
}
