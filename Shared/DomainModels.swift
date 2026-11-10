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

enum CertificateFailureReason: String, Codable, Sendable {
  case invalidAddress
  case hostNotFound
  case timedOut
  case networkUnavailable
  case connectionLost
  case cannotConnect
  case secureConnectionFailed
  case unknown

  init(from decoder: Decoder) throws {
    let rawValue = try decoder.singleValueContainer().decode(String.self)
    self = Self(rawValue: rawValue) ?? .unknown
  }

  init(error: Error?) {
    guard let error = error as? URLError else {
      self = .unknown
      return
    }
    switch error.code {
    case .cannotFindHost: self = .hostNotFound
    case .timedOut: self = .timedOut
    case .notConnectedToInternet: self = .networkUnavailable
    case .networkConnectionLost: self = .connectionLost
    case .cannotConnectToHost: self = .cannotConnect
    case .secureConnectionFailed: self = .secureConnectionFailed
    default: self = .unknown
    }
  }

  var explanation: String {
    switch self {
    case .invalidAddress: return "未能构造目标 HTTPS 地址，因此没有发出检查请求。"
    case .hostNotFound: return "系统未能解析目标域名，本次没有连接到服务器。"
    case .timedOut: return "请求在限定时间内未读取到服务器证书；仅凭超时无法断定是站点还是网络链路故障。"
    case .networkUnavailable: return "当前网络不可用，本次没有读取到服务器证书。"
    case .connectionLost: return "连接过程中网络中断，本次没有读取到服务器证书。"
    case .cannotConnect: return "未能建立到目标端口的连接，本次没有读取到服务器证书。"
    case .secureConnectionFailed: return "安全连接未能建立，本次没有读取到服务器证书。"
    case .unknown: return "本次没有读取到服务器证书，系统未提供更明确的失败类别。"
    }
  }

  func suggestion(port: Int) -> String {
    switch self {
    case .invalidAddress, .hostNotFound:
      return "核对域名与端口是否输入正确，并检查 DNS 配置。"
    case .timedOut:
      return "检查目标 HTTPS 服务；如其他端点正常，可换网络或代理路径复测。"
    case .networkUnavailable, .connectionLost:
      return "检查本机网络后，再主动刷新。"
    case .cannotConnect:
      return "检查服务器是否监听 \(port) 端口，以及防火墙或代理路径。"
    case .secureConnectionFailed:
      return "检查服务器 TLS 配置，必要时换网络或代理路径复测。"
    case .unknown:
      return "核对目标 HTTPS 服务与网络状态，然后主动刷新。"
    }
  }
}

struct HTTPResponseObservation: Codable, Sendable, Equatable {
  let statusCode: Int?
}

struct CertificateSnapshot: Codable, Identifiable, Sendable {
  let hostname: String
  let port: Int
  let checkedAt: Date
  let validFrom: Date?
  let expiresAt: Date?
  let checkState: CertificateCheckState
  let detail: String?
  let failureReason: CertificateFailureReason?
  let httpResponse: HTTPResponseObservation?
  let lastSuccessfulCheckAt: Date?
  let consecutiveFailureCount: Int

  init(
    hostname: String, checkedAt: Date, expiresAt: Date?, checkState: CertificateCheckState,
    detail: String?, lastSuccessfulCheckAt: Date? = nil, consecutiveFailureCount: Int = 0,
    port: Int = 443, validFrom: Date? = nil,
    failureReason: CertificateFailureReason? = nil, httpResponse: HTTPResponseObservation? = nil
  ) {
    self.hostname = hostname
    self.port = port
    self.checkedAt = checkedAt
    self.validFrom = validFrom
    self.expiresAt = expiresAt
    self.checkState = checkState
    self.detail = detail
    self.failureReason = failureReason
    self.httpResponse = httpResponse
    self.lastSuccessfulCheckAt = lastSuccessfulCheckAt ?? (checkState == .failed ? nil : checkedAt)
    self.consecutiveFailureCount = consecutiveFailureCount
  }

  private enum CodingKeys: String, CodingKey {
    case hostname, port, checkedAt, validFrom, expiresAt, checkState, detail
    case failureReason, httpResponse
    case lastSuccessfulCheckAt, consecutiveFailureCount
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    hostname = try values.decode(String.self, forKey: .hostname)
    port = try EndpointIdentity.decodePort(from: values)
    checkedAt = try values.decode(Date.self, forKey: .checkedAt)
    validFrom = try values.decodeIfPresent(Date.self, forKey: .validFrom)
    expiresAt = try values.decodeIfPresent(Date.self, forKey: .expiresAt)
    checkState = try values.decode(CertificateCheckState.self, forKey: .checkState)
    detail = try values.decodeIfPresent(String.self, forKey: .detail)
    failureReason = try values.decodeIfPresent(
      CertificateFailureReason.self, forKey: .failureReason)
    httpResponse = try values.decodeIfPresent(HTTPResponseObservation.self, forKey: .httpResponse)
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

  func validityRemainingFraction(at date: Date) -> Double? {
    guard let validFrom, let expiresAt, expiresAt > validFrom else { return nil }
    let fraction = expiresAt.timeIntervalSince(date) / expiresAt.timeIntervalSince(validFrom)
    return min(1, max(0, fraction))
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
