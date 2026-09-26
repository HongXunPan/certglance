import Foundation

protocol SnapshotStore: Sendable {
  func domains() throws -> [WatchedDomain]
  func snapshots() throws -> [CertificateSnapshot]
  func saveDomains(_ domains: [WatchedDomain]) throws
  func saveSnapshots(_ snapshots: [CertificateSnapshot]) throws
  func notificationTokens() throws -> Set<String>
  func saveNotificationTokens(_ tokens: Set<String>) throws
}

enum SharedStoreError: LocalizedError {
  case unavailable
  case corrupted

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "共享数据容器不可用。请检查 App 与小组件的签名及 App Group 配置。"
    case .corrupted:
      return "共享数据无法读取。请勿重复添加域名，先检查数据容器。"
    }
  }
}

final class AppGroupSnapshotStore: SnapshotStore, @unchecked Sendable {
  static let groupIdentifier = "group.com.HongXunPan.SSLWidget"

  private enum Key {
    static let domains = "watchedDomains.v1"
    static let snapshots = "certificateSnapshots.v1"
    static let notificationTokens = "notificationTokens.v1"
  }

  private let defaults: UserDefaults

  init() throws {
    guard
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: Self.groupIdentifier) != nil,
      let defaults = UserDefaults(suiteName: Self.groupIdentifier)
    else {
      throw SharedStoreError.unavailable
    }
    self.defaults = defaults
  }

  func domains() throws -> [WatchedDomain] { try read(Key.domains) }
  func snapshots() throws -> [CertificateSnapshot] { try read(Key.snapshots) }
  func notificationTokens() throws -> Set<String> {
    let tokens: [String] = try read(Key.notificationTokens)
    return Set(tokens)
  }

  func saveDomains(_ domains: [WatchedDomain]) throws { try write(domains, for: Key.domains) }
  func saveSnapshots(_ snapshots: [CertificateSnapshot]) throws {
    try write(snapshots, for: Key.snapshots)
  }
  func saveNotificationTokens(_ tokens: Set<String>) throws {
    try write(tokens.sorted(), for: Key.notificationTokens)
  }

  private func read<Value: Decodable>(_ key: String) throws -> Value
  where Value: ExpressibleByArrayLiteral {
    guard let data = defaults.data(forKey: key) else { return [] }
    do { return try JSONDecoder().decode(Value.self, from: data) } catch {
      throw SharedStoreError.corrupted
    }
  }

  private func write<Value: Encodable>(_ value: Value, for key: String) throws {
    defaults.set(try JSONEncoder().encode(value), forKey: key)
  }
}
