import Foundation

actor RegistrationChecker {
  private let directory: RDAPDirectory
  private let whois: any RegistrationWHOISQuerying
  private let http: any RegistrationFetching

  init(
    http: any RegistrationFetching = RegistrationHTTPClient(),
    whois: any RegistrationWHOISQuerying = WHOISClient()
  ) {
    self.http = http
    self.whois = whois
    directory = RDAPDirectory(http: http)
  }

  func resetDiscovery() async {
    await directory.reset()
    await whois.reset()
  }

  func check(_ domain: RegisteredDomain) async -> RegistrationSnapshot {
    let now = Date()
    do {
      try Task.checkCancellation()
      let hostname = try RegistrationInput.parse(domain.hostname)
      let tld = String(hostname.split(separator: ".").last!)
      var dates = RegistrationDates()
      var sources: [String] = []
      if let base = try await directory.service(for: tld) {
        let url = base.appendingPathComponent("domain").appendingPathComponent(hostname)
        let (data, finalURL) = try await http.get(url)
        let record = try JSONDecoder().decode(RDAPDomainRecord.self, from: data)
        dates = try record.dates(for: hostname)
        sources.append(finalURL.absoluteString)
        if dates.registrar == nil,
          let related = record.links?.first(where: {
            $0.rel == "related" && $0.type == "application/rdap+json"
              && $0.href.flatMap(URL.init(string:)).map(RegistrationHTTPClient.isPublicHTTPS)
                == true
          })?.href.flatMap(URL.init(string:))
        {
          do {
            let (registrarData, registrarURL) = try await http.get(related)
            let registrar = try JSONDecoder().decode(RDAPDomainRecord.self, from: registrarData)
            let additional = try registrar.dates(for: hostname)
            dates.registrar = additional.registrar
            dates.registry = dates.registry ?? additional.registry
            sources.append(registrarURL.absoluteString)
          } catch {
            // 保留已经成功取得的登记日期，但不把注册商查询失败隐藏成已确认续费。
            guard dates.preferred != nil else {
              throw RegistrationLookupError.message("注册商查询未完成：\(error.localizedDescription)")
            }
            return RegistrationSnapshot(
              hostname: hostname, checkedAt: now, dates: dates, checkState: .available,
              sources: sources, detail: "注册商信息未获取，续费期限需核实：\(error.localizedDescription)")
          }
        }
        if dates.preferred != nil {
          return RegistrationSnapshot(
            hostname: hostname, checkedAt: now, dates: dates, checkState: .available,
            sources: sources, detail: dates.needsConfirmation ? "登记日期不一定等于续费截止日，请向注册商核实。" : nil)
        }
      }
      try Task.checkCancellation()
      if let (supplement, source) = try await whois.lookup(hostname) {
        sources.append(source)
        return RegistrationSnapshot(
          hostname: hostname, checkedAt: now, dates: supplement,
          checkState: supplement.preferred == nil ? .noExpiration : .available, sources: sources,
          detail: "WHOIS 为未加密参考数据；缺少日期或未注明时区时不推算续费期限。")
      }
      return RegistrationSnapshot(
        hostname: hostname, checkedAt: now,
        checkState: sources.isEmpty ? .unsupported : .noExpiration, sources: sources,
        detail: "未发现更多可用的公开日期来源。")
    } catch RegistrationLookupError.http(404) {
      return RegistrationSnapshot(
        hostname: domain.hostname, checkedAt: now, checkState: .notFound,
        detail: "服务未找到匹配对象；请核对完整注册域名，不代表该域名可注册。")
    } catch {
      return RegistrationSnapshot(
        hostname: domain.hostname, checkedAt: now, checkState: .failed,
        detail: "查询未完成：\(error.localizedDescription)")
    }
  }
}
