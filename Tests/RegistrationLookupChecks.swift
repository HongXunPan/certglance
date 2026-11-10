import Foundation

enum RegistrationLookupChecks {
  private static let directoryURL = "https://data.iana.org/rdap/dns.json"
  private static let domainURL = "https://registry.example/domain/example.com"
  private static let bootstrap = """
    {"services":[[["com"],["https://registry.example/"]]]}
    """

  static func run() async throws {
    let domain = RegisteredDomain(hostname: "example.com", addedAt: .now)
    let failedDirectory = FakeRegistrationHTTP(replies: [directoryURL: .status(503)])
    let directoryChecker = RegistrationChecker(
      http: failedDirectory, whois: FakeRegistrationWHOIS())
    _ = await directoryChecker.check(domain)
    _ = await directoryChecker.check(domain)
    let directoryCalls = await failedDirectory.calls.count
    precondition(directoryCalls == 1, "发现失败也要在同批共享，禁止逐域名重复获取")
    for status in [404, 429, 503] {
      let http = FakeRegistrationHTTP(replies: [
        directoryURL: .json(bootstrap), domainURL: .status(status),
      ])
      let whois = FakeRegistrationWHOIS()
      let result = await RegistrationChecker(http: http, whois: whois).check(domain)
      precondition(result.checkState == (status == 404 ? .notFound : .failed), "HTTP 状态必须保留语义")
      let count = await whois.calls
      precondition(count == 0, "404、限流和服务错误不得触发 WHOIS 连发")
    }
    let noDates = """
      {"objectClassName":"domain","ldhName":"EXAMPLE.COM"}
      """
    let http = FakeRegistrationHTTP(replies: [
      directoryURL: .json(bootstrap), domainURL: .json(noDates),
    ])
    let whois = FakeRegistrationWHOIS()
    let checker = RegistrationChecker(http: http, whois: whois)
    let supplemented = await checker.check(domain)
    precondition(
      supplemented.checkState == .available && supplemented.dates.reported != nil,
      "正常缺日期时启用 WHOIS 补充")
    let count = await whois.calls
    precondition(count == 1, "WHOIS 仅补充一次")
    _ = await checker.check(domain)
    let discoveries = await http.calls.filter { $0 == directoryURL }.count
    precondition(discoveries == 1, "同批共享 IANA 引导发现")

    let registry = """
      {"objectClassName":"domain","ldhName":"example.com",
       "events":[{"eventAction":"expiration","eventDate":"2028-01-01T00:00:00Z"}],
       "links":[{"rel":"related","type":"application/rdap+json","href":"https://registrar.example/domain/example.com"}]}
      """
    let registrar = """
      {"objectClassName":"domain","ldhName":"example.com",
       "events":[{"eventAction":"registrar expiration","eventDate":"2027-01-01T00:00:00Z"}]}
      """
    let linked = FakeRegistrationHTTP(replies: [
      directoryURL: .json(bootstrap), domainURL: .json(registry),
      "https://registrar.example/domain/example.com": .json(registrar),
    ])
    let linkedResult = await RegistrationChecker(http: linked, whois: FakeRegistrationWHOIS())
      .check(domain)
    precondition(
      linkedResult.dates.registrar != nil && linkedResult.dates.registry != nil, "关联查询保留两类日期")
    precondition(linkedResult.sources.count == 2, "保存两种实际来源")
    let mismatch = FakeRegistrationHTTP(replies: [
      directoryURL: .json(bootstrap),
      domainURL: .json(noDates.replacingOccurrences(of: "EXAMPLE.COM", with: "OTHER.EXAMPLE")),
    ])
    let mismatched = await RegistrationChecker(http: mismatch, whois: FakeRegistrationWHOIS())
      .check(domain)
    precondition(mismatched.checkState == .failed, "身份不匹配不得当作缺日期转入 WHOIS")
    print("协议选择、错误隔离、注册商关联与发现缓存检查通过")
  }
}

private actor FakeRegistrationHTTP: RegistrationFetching {
  enum Reply: Sendable {
    case json(String)
    case status(Int)
  }
  let replies: [String: Reply]
  private(set) var calls: [String] = []

  init(replies: [String: Reply]) { self.replies = replies }

  func get(_ url: URL) async throws -> (Data, URL) {
    calls.append(url.absoluteString)
    switch replies[url.absoluteString] {
    case .json(let value): return (Data(value.utf8), url)
    case .status(let value): throw RegistrationLookupError.http(value)
    case nil: throw RegistrationLookupError.message("未声明的固定测试请求")
    }
  }
}

private actor FakeRegistrationWHOIS: RegistrationWHOISQuerying {
  private(set) var calls = 0
  func reset() {}
  func lookup(_ hostname: String) async throws -> (RegistrationDates, String)? {
    calls += 1
    return (
      RegistrationDates(reported: Date(timeIntervalSince1970: 2_000_000_000)),
      "whois://whois.example/\(hostname)"
    )
  }
}
