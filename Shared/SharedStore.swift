import Darwin
import Foundation

protocol SnapshotStore: Sendable {
  func domains() throws -> [WatchedDomain]
  func snapshots() throws -> [CertificateSnapshot]
  func replaceDomains(_ domains: [WatchedDomain]) throws
  func mergeSnapshots(_ checked: [CertificateSnapshot]) throws -> [CertificateSnapshot]
  func notificationTokens() throws -> Set<String>
  func addNotificationTokens(_ tokens: Set<String>) throws
}

enum SharedStoreError: LocalizedError {
  case unavailable
  case corrupted
  case unsafePath

  var errorDescription: String? {
    switch self {
    case .unavailable:
      return "共享数据不可用。请打开 CertGlance 检查安装与数据目录。"
    case .corrupted:
      return "共享数据无法读取。原文件已保留，请勿重复添加域名。"
    case .unsafePath:
      return "共享目录包含不安全的文件链接，请检查数据目录后重试。"
    }
  }
}

enum CertGlanceIdentity {
  static let directoryName = "com.HongXunPan.CertGlance"
  static let widgetKind = "com.HongXunPan.CertGlance.ExpiryBoard"
}

final class FileSnapshotStore: SnapshotStore, @unchecked Sendable {
  private let root: URL
  private let config: URL
  private let state: URL
  private let lockURL: URL

  convenience init(createIfNeeded: Bool) throws {
    guard let account = getpwuid(getuid()), let home = account.pointee.pw_dir else {
      throw SharedStoreError.unavailable
    }
    let homePath = String(cString: home)
    guard homePath.hasPrefix("/") else { throw SharedStoreError.unavailable }
    let root = URL(fileURLWithPath: homePath, isDirectory: true)
      .appendingPathComponent("Library/Application Support", isDirectory: true)
      .appendingPathComponent(CertGlanceIdentity.directoryName, isDirectory: true)
    try self.init(directoryURL: root, createIfNeeded: createIfNeeded)
  }

  init(directoryURL: URL, createIfNeeded: Bool) throws {
    root = directoryURL
    config = directoryURL.appendingPathComponent("config", isDirectory: true)
    state = directoryURL.appendingPathComponent("state", isDirectory: true)
    lockURL = state.appendingPathComponent("store.lock")
    if createIfNeeded {
      try prepareDirectories()
    } else {
      try verifyDirectory(config)
      try verifyDirectory(state)
    }
  }

  func domains() throws -> [WatchedDomain] {
    try read([WatchedDomain].self, from: config.appendingPathComponent("domains.v1.json"))
  }

  func snapshots() throws -> [CertificateSnapshot] {
    let hosts = Set(try domains().map(\.hostname))
    let saved: [CertificateSnapshot] = try read(
      [CertificateSnapshot].self, from: state.appendingPathComponent("snapshots.v1.json"))
    return saved.filter { hosts.contains($0.hostname) }
  }

  func replaceDomains(_ domains: [WatchedDomain]) throws {
    try withLock {
      let hosts = Set(domains.map(\.hostname))
      let saved: [CertificateSnapshot] = try read(
        [CertificateSnapshot].self, from: state.appendingPathComponent("snapshots.v1.json"))
      try write(
        saved.filter { hosts.contains($0.hostname) },
        to: state.appendingPathComponent("snapshots.v1.json"))
      try write(domains, to: config.appendingPathComponent("domains.v1.json"))
    }
  }

  func mergeSnapshots(_ checked: [CertificateSnapshot]) throws -> [CertificateSnapshot] {
    try withLock {
      let hosts = Set(try domains().map(\.hostname))
      let saved: [CertificateSnapshot] = try read(
        [CertificateSnapshot].self, from: state.appendingPathComponent("snapshots.v1.json"))
      var byHost = Dictionary(uniqueKeysWithValues: saved.map { ($0.hostname, $0) })
      for result in checked where hosts.contains(result.hostname) {
        let old = byHost[result.hostname]
        if let old, result.checkedAt <= old.checkedAt { continue }
        let succeeded = result.checkState != .failed
        let previousFailures = old?.consecutiveFailureCount ?? 0
        let failureCount =
          succeeded ? 0 : (previousFailures == Int.max ? Int.max : previousFailures + 1)
        byHost[result.hostname] = CertificateSnapshot(
          hostname: result.hostname, checkedAt: result.checkedAt,
          expiresAt: result.expiresAt ?? (succeeded ? nil : old?.expiresAt),
          checkState: result.checkState, detail: result.detail,
          lastSuccessfulCheckAt: succeeded ? result.checkedAt : old?.lastSuccessfulCheckAt,
          consecutiveFailureCount: failureCount)
      }
      let merged = byHost.values.filter { hosts.contains($0.hostname) }
        .sorted { $0.hostname < $1.hostname }
      try write(merged, to: state.appendingPathComponent("snapshots.v1.json"))
      return merged
    }
  }

  func notificationTokens() throws -> Set<String> {
    let saved: [String] = try read(
      [String].self, from: state.appendingPathComponent("notification-tokens.v1.json"))
    return Set(saved)
  }

  func addNotificationTokens(_ tokens: Set<String>) throws {
    try withLock {
      let saved: [String] = try read(
        [String].self, from: state.appendingPathComponent("notification-tokens.v1.json"))
      try write(
        Set(saved).union(tokens).sorted(),
        to: state.appendingPathComponent("notification-tokens.v1.json"))
    }
  }

  private func prepareDirectories() throws {
    for directory in [root, config, state] {
      if FileManager.default.fileExists(atPath: directory.path) {
        try verifyDirectory(directory)
      } else {
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
  }

  private func verifyDirectory(_ directory: URL) throws {
    var info = stat()
    guard lstat(directory.path, &info) == 0 else {
      throw errno == ENOENT ? SharedStoreError.unavailable : SharedStoreError.unsafePath
    }
    guard (info.st_mode & S_IFMT) == S_IFDIR,
      info.st_uid == getuid()
    else {
      throw SharedStoreError.unsafePath
    }
  }

  private func withLock<Value>(_ body: () throws -> Value) throws -> Value {
    let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw SharedStoreError.unavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw SharedStoreError.unavailable }
    defer { flock(descriptor, LOCK_UN) }
    return try body()
  }

  private func read<Value: Decodable & ExpressibleByArrayLiteral>(
    _ type: Value.Type, from url: URL
  ) throws -> Value {
    var info = stat()
    if lstat(url.path, &info) != 0 {
      if errno == ENOENT { return [] }
      throw SharedStoreError.unavailable
    }
    guard (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == getuid() else {
      throw SharedStoreError.unsafePath
    }
    let data: Data
    do { data = try Data(contentsOf: url) } catch { throw SharedStoreError.unavailable }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw SharedStoreError.corrupted
    }
  }

  private func write<Value: Encodable>(_ value: Value, to url: URL) throws {
    var info = stat()
    if lstat(url.path, &info) == 0 {
      try verifyRegularFile(url)
    } else if errno != ENOENT {
      throw SharedStoreError.unavailable
    }
    let data = try JSONEncoder().encode(value)
    try data.write(to: url, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  private func verifyRegularFile(_ url: URL) throws {
    var info = stat()
    guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
      info.st_uid == getuid()
    else {
      throw SharedStoreError.unsafePath
    }
  }
}
