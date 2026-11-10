import Foundation

enum RegistrationDateParser {
  static func parse(_ text: String) -> Date? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: value), RegistrationDates.isValidDate(date) { return date }
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: value), RegistrationDates.isValidDate(date) { return date }
    // 只接受明确时区，不凭本机时区猜测注册局的日期。
    let formats = [
      "yyyy-MM-dd HH:mm:ss 'UTC'", "yyyy.MM.dd HH:mm:ss 'UTC'", "yyyy-MM-dd HH:mm:ss Z",
    ]
    for format in formats {
      let parser = DateFormatter()
      parser.locale = Locale(identifier: "en_US_POSIX")
      parser.timeZone = TimeZone(secondsFromGMT: 0)
      parser.dateFormat = format
      parser.isLenient = false
      if let date = parser.date(from: value), RegistrationDates.isValidDate(date),
        parser.string(from: date) == value
      {
        return date
      }
    }
    return nil
  }
}

struct RDAPDomainRecord: Decodable, Sendable {
  struct Event: Decodable, Sendable {
    let eventAction: String
    let eventDate: String
  }
  struct Link: Decodable, Sendable {
    let rel: String?
    let href: String?
    let type: String?
  }
  let objectClassName: String
  let ldhName: String?
  let events: [Event]?
  let links: [Link]?

  func dates(for hostname: String) throws -> RegistrationDates {
    guard objectClassName == "domain",
      let ldhName, (try? DomainInput.normalize(ldhName)) == hostname
    else { throw RegistrationLookupError.message("服务返回的域名身份不匹配，请核对完整注册域名。") }
    var dates = RegistrationDates()
    for event in events ?? [] {
      guard event.eventAction == "expiration" || event.eventAction == "registrar expiration" else {
        continue
      }
      guard let value = RegistrationDateParser.parse(event.eventDate) else {
        throw RegistrationLookupError.message("服务返回的到期日期格式无法识别。")
      }
      if event.eventAction == "registrar expiration" {
        try Self.assign(value, to: &dates.registrar)
      } else {
        try Self.assign(value, to: &dates.registry)
      }
    }
    return dates
  }

  private static func assign(_ value: Date, to target: inout Date?) throws {
    guard target == nil || target == value else {
      throw RegistrationLookupError.message("服务返回多个冲突的同类到期日期，请向注册商核对。")
    }
    target = value
  }
}

enum WHOISParser {
  static func fields(_ text: String) -> [(String, String)] {
    let lines = text.components(separatedBy: .newlines)
    return lines.enumerated().compactMap { index, line in
      let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { return nil }
      let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
      var value = parts[1].trimmingCharacters(in: .whitespaces)
      if value.isEmpty, index + 1 < lines.count {
        value = lines[index + 1].trimmingCharacters(in: .whitespaces)
      }
      return (key, value)
    }
  }

  static func server(in text: String) -> String? {
    guard let value = fields(text).first(where: { $0.0 == "whois" })?.1,
      let host = try? RegistrationInput.parse(value), host == value.lowercased()
    else { return nil }
    return host
  }

  static func dates(in text: String, hostname: String) throws -> RegistrationDates {
    let values = fields(text)
    let identities = values.filter { ["domain name", "domain", "domain-name"].contains($0.0) }
      .compactMap { try? DomainInput.normalize($0.1) }
    guard !identities.isEmpty, identities.allSatisfy({ $0 == hostname }) else {
      throw RegistrationLookupError.message("WHOIS 未返回匹配的域名身份；请核对注册域名，或稍后主动重试。")
    }
    var dates = RegistrationDates()
    for (key, raw) in values {
      let kind: Int
      switch key {
      case "registrar registration expiration date": kind = 0
      case "registry expiry date": kind = 1
      case "expiration time", "expiration date", "expiry date", "expires on", "paid-till",
        "expire-date", "renewal date":
        kind = 2
      default: continue
      }
      guard let date = RegistrationDateParser.parse(raw) else { continue }
      switch kind {
      case 0: try assign(date, to: &dates.registrar)
      case 1: try assign(date, to: &dates.registry)
      default: try assign(date, to: &dates.reported)
      }
    }
    return dates
  }

  private static func assign(_ date: Date, to target: inout Date?) throws {
    guard target == nil || target == date else {
      throw RegistrationLookupError.message("WHOIS 返回多个冲突的同类日期，无法安全选择。")
    }
    target = date
  }
}
