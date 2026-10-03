import Foundation

@main
struct ModelChecks {
  static func main() throws {
    let normalized = try DomainInput.normalize(" Example.COM. ")
    expect(normalized == "example.com", "域名应统一小写并移除末尾根点")
    for invalid in [
      "https://example.com", "example.com:443", ".example.com", "example..com", "-a.com",
    ] {
      expect((try? DomainInput.normalize(invalid)) == nil, "应拒绝无效域名：\(invalid)")
    }
    let pasted = try DomainInput.parseEndpoint(" HTTPS://Example.COM:8443/a/b?q=1#part ")
    expect(pasted.hostname == "example.com" && pasted.port == 8443, "粘贴网址应提取 HTTPS 主机和端口")
    let bare = try DomainInput.parseEndpoint("example.com:9443/path")
    expect(bare.hostname == "example.com" && bare.port == 9443, "裸端点与路径应按 HTTPS 解析")
    let http = try DomainInput.parseEndpoint("http://example.com/article")
    expect(http.hostname == "example.com" && http.port == 443, "无端口 HTTP 网址仅提取主机")
    let defaultPort = try DomainInput.parseEndpoint("https://example.com:443/path")
    expect(defaultPort.hostname == "example.com" && defaultPort.port == 443, "显式 443 应归一")
    for invalid in [
      "http://example.com:80/path", "ftp://example.com", "https://a@b.com/path",
      "https://example.com:0", "https://example.com:65536", "example.com:abc",
    ] {
      expect((try? DomainInput.parseEndpoint(invalid)) == nil, "应拒绝无效端点：\(invalid)")
    }
    let legacyDomain = try JSONDecoder().decode(
      WatchedDomain.self, from: Data("{\"hostname\":\"example.com\",\"addedAt\":1000}".utf8))
    expect(legacyDomain.port == 443 && legacyDomain.id == "example.com", "旧域名应归属 443")
    let alternate = WatchedDomain(hostname: "example.com", port: 8443, addedAt: .now)
    expect(alternate.id == "example.com:8443", "自定义端口应拥有独立标识")

    let now = Date(timeIntervalSince1970: 1_000_000)
    func snapshot(days: Double, state: CertificateCheckState = .trusted) -> CertificateSnapshot {
      CertificateSnapshot(
        hostname: "example.com", checkedAt: now,
        expiresAt: now.addingTimeInterval(days * 86_400),
        checkState: state, detail: nil)
    }
    expect(snapshot(days: 60).severity(at: now) == .healthy, "60 天应为正常")
    expect(snapshot(days: 20).severity(at: now) == .watch, "20 天应为关注")
    expect(snapshot(days: 5).severity(at: now) == .soon, "5 天应为临近")
    expect(snapshot(days: 0.5).severity(at: now) == .critical, "不足一天应为紧急")
    expect(snapshot(days: -1).severity(at: now) == .expired, "已过期应优先呈现")
    expect(snapshot(days: 60, state: .untrusted).severity(at: now) == .untrusted, "不受信任不得显示为正常")
    expect(snapshot(days: 60, state: .failed).severity(at: now) == .checkFailed, "连接失败不得显示为正常")

    let validity = CertificateSnapshot(
      hostname: "example.com", checkedAt: now,
      expiresAt: now.addingTimeInterval(45 * 86_400),
      checkState: .trusted, detail: nil,
      validFrom: now.addingTimeInterval(-45 * 86_400))
    expect(validity.validityRemainingFraction(at: now) == 0.5, "圆环应表示完整有效期剩余比例")
    expect(
      validity.validityRemainingFraction(at: now.addingTimeInterval(-50 * 86_400)) == 1,
      "有效期开始前比例应限制为满环")
    expect(
      validity.validityRemainingFraction(at: now.addingTimeInterval(50 * 86_400)) == 0,
      "到期后比例应限制为零")
    expect(snapshot(days: 45).validityRemainingFraction(at: now) == nil, "旧快照不得伪造比例")
    let invalidValidity = CertificateSnapshot(
      hostname: "example.com", checkedAt: now, expiresAt: now,
      checkState: .trusted, detail: nil, validFrom: now)
    expect(invalidValidity.validityRemainingFraction(at: now) == nil, "无效证书周期不得展示圆环")

    let domains = ["healthy.example", "expired.example"].map {
      WatchedDomain(hostname: $0, addedAt: now)
    }
    let snapshots = [
      CertificateSnapshot(
        hostname: "healthy.example", checkedAt: now,
        expiresAt: now.addingTimeInterval(60 * 86_400),
        checkState: .trusted, detail: nil),
      CertificateSnapshot(
        hostname: "expired.example", checkedAt: now,
        expiresAt: now.addingTimeInterval(-86_400),
        checkState: .trusted, detail: nil),
    ]
    expect(
      DashboardOrder.sorted(domains, snapshots: snapshots, at: now).first?.hostname
        == "expired.example",
      "看板应聚焦最紧急的域名")

    let future = NotificationPolicy.moments(
      expiresAt: now.addingTimeInterval(60 * 86_400), now: now)
    expect(future.map(\.threshold) == [30, 7, 1], "远期证书应计划三个提醒档位")
    expect(future.allSatisfy { $0.date != nil }, "远期提醒应有确定触发时间")
    let withinSeven = NotificationPolicy.moments(
      expiresAt: now.addingTimeInterval(5 * 86_400), now: now)
    expect(withinSeven.map(\.threshold) == [7, 1], "临近到期只保留当前和未来档位")
    expect(withinSeven.first?.date == nil, "已跨过的最近档位应立即提醒")
    let expired = NotificationPolicy.moments(
      expiresAt: now.addingTimeInterval(-86_400), now: now)
    expect(expired.map(\.threshold) == [0], "过期证书只应计划一次过期提醒")
    expect(
      NotificationPolicy.schedulingAction(
        for: future[0], alreadyPending: true, tokenRecorded: false) == .skip,
      "已排程的未来提醒不能被改成即时提醒")
    expect(
      NotificationPolicy.schedulingAction(
        for: future[0], alreadyPending: false, tokenRecorded: false)
        == .future(future[0].date!),
      "未排程的未来提醒应保留原触发日期")
    expect(
      NotificationPolicy.schedulingAction(
        for: withinSeven[0], alreadyPending: false, tokenRecorded: false) == .immediate,
      "刚进入提醒窗口时应立即提醒")
    expect(
      NotificationPolicy.schedulingAction(
        for: withinSeven[0], alreadyPending: true, tokenRecorded: false) == .skip,
      "已在待投递队列中的即时提醒不得重复安排")
    print("模型定点检查通过")
  }

  private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
  }
}
