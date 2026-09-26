import Foundation

struct WatchedDomain: Codable, Hashable, Identifiable, Sendable {
  let hostname: String
  let addedAt: Date

  var id: String { hostname }
}

enum DomainInputError: LocalizedError {
  case invalid
  case duplicate

  var errorDescription: String? {
    switch self {
    case .invalid:
      return "请输入域名，例如 example.com；不要包含协议、端口或路径。"
    case .duplicate:
      return "这个域名已经在看板中。"
    }
  }
}

enum DomainInput {
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
  let checkedAt: Date
  let expiresAt: Date?
  let checkState: CertificateCheckState
  let detail: String?

  var id: String { hostname }

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
    let indexed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.hostname, $0) })
    return domains.sorted { left, right in
      let leftSeverity = indexed[left.hostname]?.severity(at: date) ?? .unchecked
      let rightSeverity = indexed[right.hostname]?.severity(at: date) ?? .unchecked
      if leftSeverity != rightSeverity { return leftSeverity.rawValue < rightSeverity.rawValue }
      let leftExpiry = indexed[left.hostname]?.expiresAt ?? .distantFuture
      let rightExpiry = indexed[right.hostname]?.expiresAt ?? .distantFuture
      if leftExpiry != rightExpiry { return leftExpiry < rightExpiry }
      return left.hostname < right.hostname
    }
  }
}
