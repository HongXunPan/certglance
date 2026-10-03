import Foundation

struct WatchedDomain: Codable, Hashable, Identifiable, Sendable {
  let hostname: String
  let port: Int
  let addedAt: Date

  init(hostname: String, port: Int = 443, addedAt: Date) {
    self.hostname = hostname
    self.port = port
    self.addedAt = addedAt
  }

  private enum CodingKeys: String, CodingKey { case hostname, port, addedAt }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    hostname = try values.decode(String.self, forKey: .hostname)
    port = try EndpointIdentity.decodePort(from: values)
    addedAt = try values.decode(Date.self, forKey: .addedAt)
  }

  var id: String { EndpointIdentity.key(hostname: hostname, port: port) }
  var displayName: String { id }
}

enum EndpointIdentity {
  static func key(hostname: String, port: Int) -> String {
    port == 443 ? hostname : "\(hostname):\(port)"
  }

  static func decodePort<Keys: CodingKey>(
    from values: KeyedDecodingContainer<Keys>
  ) throws -> Int where Keys: RawRepresentable, Keys.RawValue == String {
    guard let key = Keys(rawValue: "port") else { return 443 }
    let port = try values.decodeIfPresent(Int.self, forKey: key) ?? 443
    guard (1...65_535).contains(port) else {
      throw DecodingError.dataCorruptedError(
        forKey: key, in: values, debugDescription: "HTTPS 端口必须在 1 至 65535 之间")
    }
    return port
  }
}

enum DomainInputError: LocalizedError {
  case invalid
  case duplicate

  var errorDescription: String? {
    switch self {
    case .invalid:
      return "请输入有效域名、域名:端口或 HTTPS 网址；HTTP 网址不能指定端口。"
    case .duplicate:
      return "这个 HTTPS 端点已经在看板中。"
    }
  }
}

enum DomainInput {
  static func parseEndpoint(_ input: String) throws -> (hostname: String, port: Int) {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw DomainInputError.invalid }
    let hasScheme = trimmed.contains("://")
    let components = URLComponents(string: hasScheme ? trimmed : "https://\(trimmed)")
    guard let components,
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      components.user == nil, components.password == nil,
      let host = components.host,
      !host.isEmpty,
      scheme == "https" || components.port == nil
    else {
      throw DomainInputError.invalid
    }
    let hostname = try normalize(host)
    let port = components.port ?? 443
    guard (1...65_535).contains(port) else { throw DomainInputError.invalid }
    return (hostname, port)
  }

  static func normalize(_ input: String) throws -> String {
    let lowered = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let hostname = lowered.hasSuffix(".") ? String(lowered.dropLast()) : lowered
    let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
    guard hostname.utf8.count <= 253, labels.count >= 2,
      labels.allSatisfy({ label in
        let bytes = Array(label.utf8)
        return !bytes.isEmpty && bytes.count <= 63
          && bytes.first != 45 && bytes.last != 45
          && bytes.allSatisfy { byte in
            (97...122).contains(byte) || (48...57).contains(byte) || byte == 45
          }
      })
    else {
      throw DomainInputError.invalid
    }
    return hostname
  }
}

enum CertificateCheckState: String, Codable, Sendable {
  case trusted
  case untrusted
  case failed
}

struct CertificateSnapshot: Codable, Identifiable, Sendable {
  let hostname: String
  let port: Int
  let checkedAt: Date
  let expiresAt: Date?
  let checkState: CertificateCheckState
  let detail: String?
  let lastSuccessfulCheckAt: Date?
  let consecutiveFailureCount: Int

  init(
    hostname: String, checkedAt: Date, expiresAt: Date?, checkState: CertificateCheckState,
    detail: String?, lastSuccessfulCheckAt: Date? = nil, consecutiveFailureCount: Int = 0,
    port: Int = 443
  ) {
    self.hostname = hostname
    self.port = port
    self.checkedAt = checkedAt
    self.expiresAt = expiresAt
    self.checkState = checkState
    self.detail = detail
    self.lastSuccessfulCheckAt = lastSuccessfulCheckAt ?? (checkState == .failed ? nil : checkedAt)
    self.consecutiveFailureCount = consecutiveFailureCount
  }

  private enum CodingKeys: String, CodingKey {
    case hostname, port, checkedAt, expiresAt, checkState, detail
    case lastSuccessfulCheckAt, consecutiveFailureCount
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    hostname = try values.decode(String.self, forKey: .hostname)
    port = try EndpointIdentity.decodePort(from: values)
    checkedAt = try values.decode(Date.self, forKey: .checkedAt)
    expiresAt = try values.decodeIfPresent(Date.self, forKey: .expiresAt)
    checkState = try values.decode(CertificateCheckState.self, forKey: .checkState)
    detail = try values.decodeIfPresent(String.self, forKey: .detail)
    lastSuccessfulCheckAt =
      try values.decodeIfPresent(Date.self, forKey: .lastSuccessfulCheckAt)
      ?? (checkState == .failed ? nil : checkedAt)
    let failures = try values.decodeIfPresent(Int.self, forKey: .consecutiveFailureCount) ?? 0
    guard failures >= 0 else {
      throw DecodingError.dataCorruptedError(
        forKey: .consecutiveFailureCount, in: values, debugDescription: "连续失败次数不能为负数")
    }
    consecutiveFailureCount = failures
  }

  var id: String { EndpointIdentity.key(hostname: hostname, port: port) }
  var displayName: String { id }

  func daysRemaining(at date: Date) -> Int? {
    guard let expiresAt else { return nil }
    return Int(ceil(expiresAt.timeIntervalSince(date) / 86_400))
  }

  func severity(at date: Date) -> CertificateSeverity {
    if checkState == .failed { return .checkFailed }
    guard let expiresAt else { return .checkFailed }
    if expiresAt <= date { return .expired }
    if checkState == .untrusted { return .untrusted }
    let days = daysRemaining(at: date) ?? 0
    if days <= 1 { return .critical }
    if days <= 7 { return .soon }
    if days <= 30 { return .watch }
    return .healthy
  }
}

enum CertificateSeverity: Int, Sendable {
  case expired = 0
  case checkFailed = 1
  case untrusted = 2
  case critical = 3
  case soon = 4
  case watch = 5
  case healthy = 6
  case unchecked = 7

  var label: String {
    switch self {
    case .expired: return "已过期"
    case .checkFailed: return "检查失败"
    case .untrusted: return "不受信任"
    case .critical: return "即将到期"
    case .soon: return "临近到期"
    case .watch: return "需要关注"
    case .healthy: return "正常"
    case .unchecked: return "待检查"
    }
  }

  var symbol: String {
    switch self {
    case .expired, .checkFailed, .untrusted: return "exclamationmark.shield.fill"
    case .critical, .soon, .watch: return "clock.badge.exclamationmark"
    case .healthy: return "checkmark.shield.fill"
    case .unchecked: return "shield.lefthalf.filled"
    }
  }
}

enum DashboardOrder {
  static func sorted(_ domains: [WatchedDomain], snapshots: [CertificateSnapshot], at date: Date)
    -> [WatchedDomain]
  {
    let indexed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    return domains.sorted { left, right in
      let leftSeverity = indexed[left.id]?.severity(at: date) ?? .unchecked
      let rightSeverity = indexed[right.id]?.severity(at: date) ?? .unchecked
      if leftSeverity != rightSeverity { return leftSeverity.rawValue < rightSeverity.rawValue }
      let leftExpiry = indexed[left.id]?.expiresAt ?? .distantFuture
      let rightExpiry = indexed[right.id]?.expiresAt ?? .distantFuture
      if leftExpiry != rightExpiry { return leftExpiry < rightExpiry }
      return left.id < right.id
    }
  }
}
