import Foundation

enum RegistrationWidgetIdentity {
  static let kind = "com.HongXunPan.CertGlance.RegistrationExpiry"
}

struct RegisteredDomain: Codable, Hashable, Identifiable, Sendable {
  let hostname: String
  let addedAt: Date
  var id: String { hostname }
}

enum RegistrationInput {
  static func parse(_ input: String) throws -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
      throw RegistrationLookupError.message("注册域名不能包含控制字符。")
    }
    // URLComponents.host 会把 Punycode 展开成 Unicode；URL.host 保留可查询的 A-label。
    let components = URLComponents(string: trimmed.contains("://") ? trimmed : "https://\(trimmed)")
    guard let components, ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
      components.user == nil, components.password == nil, let asciiHost = components.url?.host()
    else { throw RegistrationLookupError.message("请输入完整注册域名或 HTTP(S) 网址。") }
    let host = try DomainInput.normalize(asciiHost)
    guard let last = host.split(separator: ".").last,
      !last.allSatisfy(\.isNumber), host != "localhost", !host.hasSuffix(".local"),
      !host.hasSuffix(".localhost")
    else { throw RegistrationLookupError.message("请输入完整注册域名，不支持 IP 或本地主机。") }
    return host
  }
}

enum RegistrationCheckState: String, Codable, Sendable {
  case available, noExpiration, notFound, unsupported, failed
}

struct RegistrationDates: Codable, Equatable, Sendable {
  var registrar: Date?
  var registry: Date?
  var reported: Date?

  var preferred: Date? { registrar ?? registry ?? reported }
  var basis: String {
    if registrar != nil { return "注册商到期日" }
    if registry != nil { return "注册局到期日" }
    return "服务报告日期"
  }
  var needsConfirmation: Bool { registrar == nil }
  var hasDifferentDates: Bool {
    guard let registrar, let registry else { return false }
    return registrar != registry
  }

  var isValid: Bool {
    [registrar, registry, reported].compactMap { $0 }.allSatisfy(Self.isValidDate)
  }

  static func isValidDate(_ date: Date) -> Bool {
    let seconds = date.timeIntervalSince1970
    return seconds.isFinite && seconds >= -62_135_596_800 && seconds < 253_402_300_800
  }
}

struct RegistrationSnapshot: Codable, Identifiable, Sendable {
  let hostname: String
  let checkedAt: Date
  var dates: RegistrationDates
  let checkState: RegistrationCheckState
  var sources: [String]
  let detail: String?
  var lastSuccessfulCheckAt: Date?
  var id: String { hostname }

  init(
    hostname: String, checkedAt: Date, dates: RegistrationDates = RegistrationDates(),
    checkState: RegistrationCheckState, sources: [String] = [], detail: String? = nil,
    lastSuccessfulCheckAt: Date? = nil
  ) {
    self.hostname = hostname
    self.checkedAt = checkedAt
    self.dates = dates
    self.checkState = checkState
    self.sources = sources
    self.detail = detail
    self.lastSuccessfulCheckAt =
      lastSuccessfulCheckAt ?? (checkState == .available ? checkedAt : nil)
  }

  func daysRemaining(at date: Date) -> Int? {
    guard let expiry = dates.preferred, RegistrationDates.isValidDate(expiry),
      RegistrationDates.isValidDate(date)
    else { return nil }
    return Int(ceil(expiry.timeIntervalSince(date) / 86_400))
  }

  func label(at date: Date) -> String {
    switch checkState {
    case .failed: return "查询失败"
    case .notFound: return "未找到匹配记录"
    case .unsupported: return "暂无可用查询服务"
    case .noExpiration: return "服务未提供到期日期"
    case .available:
      if dates.needsConfirmation { return "续费期限需核实" }
      if let expiry = dates.preferred, expiry <= date { return "注册商到期日已到" }
      return (daysRemaining(at: date) ?? 0) <= 30 ? "临近到期" : "已获取到期日期"
    }
  }

  func needsAttention(at date: Date) -> Bool {
    checkState != .available || dates.needsConfirmation || (daysRemaining(at: date) ?? 0) <= 30
      || date.timeIntervalSince(lastSuccessfulCheckAt ?? .distantPast) > 48 * 3_600
  }
}

enum RegistrationPlanning {
  static let checkInterval: TimeInterval = 24 * 3_600
  static let activityInterval: TimeInterval = 30 * 60

  static func due(
    _ domains: [RegisteredDomain], snapshots: [RegistrationSnapshot], at date: Date,
    force: Bool = false
  ) -> [RegisteredDomain] {
    let indexed = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
    return domains.filter {
      force || indexed[$0.id].map { date.timeIntervalSince($0.checkedAt) >= checkInterval } ?? true
    }.sorted {
      let left = indexed[$0.id]?.checkedAt ?? .distantPast
      let right = indexed[$1.id]?.checkedAt ?? .distantPast
      return left == right ? $0.id < $1.id : left < right
    }
  }
}

enum RegistrationLookupError: LocalizedError, Sendable {
  case message(String)
  case http(Int)

  var errorDescription: String? {
    switch self {
    case .message(let message): return message
    case .http(429): return "查询服务限流，请稍后主动重试。"
    case .http(let code): return "查询服务返回 HTTP \(code)，请稍后主动重试。"
    }
  }
}
