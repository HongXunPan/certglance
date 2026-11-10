import Foundation

@main
struct RegistrationChecks {
  static func main() async {
    do {
      try await run()
    } catch {
      FileHandle.standardError.write(Data("注册域名检查失败：\(error.localizedDescription)\n".utf8))
      exit(1)
    }
  }

  private static func run() async throws {
    if CommandLine.arguments.contains("--whois-network") {
      guard let (dates, _) = try await WHOISClient().lookup("example.com"), dates.preferred != nil
      else {
        throw RegistrationLookupError.message("WHOIS 未取得匹配域名的公开日期。")
      }
      print("WHOIS 公开域名检查通过：example.com；日期为未加密参考数据。")
      return
    }
    if CommandLine.arguments.contains("--network") {
      let result = await RegistrationChecker().check(
        RegisteredDomain(hostname: "example.com", addedAt: .now))
      guard result.checkState == .available, result.hostname == "example.com",
        result.dates.preferred != nil, !result.sources.isEmpty
      else { throw RegistrationLookupError.message(result.detail ?? "未获取有效注册日期") }
      print("公开域名网络检查通过：example.com，\(result.dates.basis)；日期为动态数据。")
      return
    }
    guard CommandLine.arguments.count == 2 else { fatalError("请传入本仓受管临时目录") }
    try parsingChecks()
    try await RegistrationLookupChecks.run()
    try storeChecks(parent: URL(fileURLWithPath: CommandLine.arguments[1]))
    print("注册域名输入、解析、周期与仓储检查通过")
  }

  private static func parsingChecks() throws {
    expect(
      try RegistrationInput.parse(" https://Example.COM:8443/path ") == "example.com", "注册身份不含端口")
    expect(try RegistrationInput.parse("example.co.uk") == "example.co.uk", "不能截取最后两段")
    expect(try RegistrationInput.parse("xn--fiqs8s.example") == "xn--fiqs8s.example", "接受 Punycode")
    expect((try? RegistrationInput.parse("127.0.0.1")) == nil, "不接受 IP")
    expect((try? RegistrationInput.parse("example.com\r\nother")) == nil, "防止 WHOIS 查询注入")
    let json = """
      {"objectClassName":"domain","ldhName":"EXAMPLE.COM","events":[
        {"eventAction":"expiration","eventDate":"2028-01-01T00:00:00Z"},
        {"eventAction":"registrar expiration","eventDate":"2027-01-01T00:00:00Z"}]}
      """
    let record = try JSONDecoder().decode(RDAPDomainRecord.self, from: Data(json.utf8))
    let dates = try record.dates(for: "example.com")
    expect(dates.registrar != dates.registry, "保留两种不同含义日期")
    expect(dates.hasDifferentDates, "日期不同时必须提示用户核对")
    expect(
      !RegistrationDates(registrar: Date(timeIntervalSince1970: 1e100)).isValid, "异常时间不得溢出天数或通知标识")
    expect(dates.preferred == dates.registrar && !dates.needsConfirmation, "优先注册商日期")
    expect((try? record.dates(for: "sub.example.com")) == nil, "禁止冒用父域名日期")
    expect(RegistrationDateParser.parse("2027-01-01 00:00:00") == nil, "不猜测无时区时间")
    expect(RegistrationDateParser.parse("2027-01-01 00:00:00 UTC") != nil, "接受明确 UTC")
    let whois = """
      Domain Name: EXAMPLE.COM
      Registry Expiry Date: 2028-01-01T00:00:00Z
      Registrar Registration Expiration Date: 2027-01-01T00:00:00Z
      """
    expect(try WHOISParser.dates(in: whois, hostname: "example.com") == dates, "WHOIS 日期含义隔离")
    expect((try? WHOISParser.dates(in: whois, hostname: "sub.example.com")) == nil, "WHOIS 身份必须匹配")
    expect(
      try WHOISParser.dates(
        in: "Domain: example.com\npaid-till: 2027-01-01", hostname: "example.com"
      ).preferred == nil, "不将无时区日期伪装为精确时刻")
    expect(
      WHOISParser.server(in: "domain: CN\nwhois: whois.cnnic.cn") == "whois.cnnic.cn",
      "解析 IANA 服务发现")
    let now = Date(timeIntervalSince1970: 1_000_000)
    let domain = RegisteredDomain(hostname: "example.com", addedAt: now)
    let snapshot = RegistrationSnapshot(
      hostname: domain.id, checkedAt: now, dates: dates, checkState: .available)
    let notificationIDs = RegistrationNotificationPolicy.validIdentifiers(
      snapshots: [snapshot], preferences: .standard)
    expect(notificationIDs.count == 4, "注册提醒包含三档及到期档位")
    expect(
      notificationIDs.allSatisfy { $0.hasPrefix("certglance.registration.") }, "注册通知与 TLS 前缀隔离")
    expect(
      RegistrationNotificationPolicy.validIdentifiers(snapshots: [], preferences: .standard)
        .isEmpty, "移除域名清理待发提醒")
    expect(RegistrationPlanning.due([domain], snapshots: [], at: now).count == 1, "首次应检查")
    expect(RegistrationPlanning.due([domain], snapshots: [snapshot], at: now).isEmpty, "周期内不重复查询")
    expect(
      RegistrationPlanning.due([domain], snapshots: [snapshot], at: now.addingTimeInterval(86_400))
        .count == 1, "一天后进入队列")
    expect(
      RegistrationPlanning.due([domain], snapshots: [snapshot], at: now, force: true).count == 1,
      "主动检查可忽略周期")
    expect(
      !RegistrationHTTPClient.isPublicHTTPS(URL(string: "http://example.com")!), "不允许 HTTP 查询或跳转")
    expect(!RegistrationHTTPClient.isPublicHTTPS(URL(string: "https://127.0.0.1")!), "不允许 IP 服务地址")
  }

  private static func storeChecks(parent: URL) throws {
    let root = parent.appendingPathComponent("registration-check-20261102-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try FileSnapshotStore(directoryURL: root, createIfNeeded: true)
    expect(try store.registeredDomains().isEmpty, "旧数据不需要迁移")
    let now = Date(timeIntervalSince1970: 1_000_000)
    let domain = RegisteredDomain(hostname: "example.com", addedAt: now)
    try store.replaceRegisteredDomains([domain])
    let dates = RegistrationDates(registrar: now.addingTimeInterval(86_400))
    let good = RegistrationSnapshot(
      hostname: domain.id, checkedAt: now, dates: dates, checkState: .available,
      sources: ["https://example.com/domain/example.com"])
    try store.mergeRegistrationSnapshots([good])
    let failed = RegistrationSnapshot(
      hostname: domain.id, checkedAt: now.addingTimeInterval(1), checkState: .failed)
    try store.mergeRegistrationSnapshots([failed])
    let saved = try store.registrationSnapshots().first!
    expect(saved.dates == dates && saved.checkState == .failed, "失败保留旧日期但不能显示健康")
    expect(saved.lastSuccessfulCheckAt == now, "失败不伪造成功时间")
    try store.mergeRegistrationSnapshots([good])
    expect(try store.registrationSnapshots().first?.checkState == .failed, "旧结果不能覆盖新状态")
    try store.replaceRegisteredDomains([])
    try store.mergeRegistrationSnapshots([good])
    expect(try store.registrationSnapshots().isEmpty, "删除后不复活结果")
    try store.replaceRegisteredDomains([domain])
    expect(try store.registrationSnapshots().isEmpty, "重新添加不复活旧快照")
    let path = root.appendingPathComponent("config/registrations.v1.json")
    let corrupt = Data("损坏的 JSON".utf8)
    try corrupt.write(to: path)
    expect((try? store.replaceRegisteredDomains([])) == nil, "配置损坏阻止覆盖")
    expect(try Data(contentsOf: path) == corrupt, "保留损坏文件")
    expect(try store.domains().isEmpty, "注册配置损坏不影响旧证书仓储")
  }

  private static func expect(_ condition: Bool, _ message: String) {
    precondition(condition, message)
  }
}
