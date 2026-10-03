import Foundation
import Security

struct CertificateChecker: Sendable {
  func check(_ hostname: String) async -> CertificateSnapshot {
    await check(WatchedDomain(hostname: hostname, addedAt: .now))
  }

  func check(_ domain: WatchedDomain) async -> CertificateSnapshot {
    let checkedAt = Date()
    var components = URLComponents()
    components.scheme = "https"
    components.host = domain.hostname
    components.port = domain.port
    components.path = "/"
    guard let url = components.url else {
      return CertificateSnapshot(
        hostname: domain.hostname, checkedAt: checkedAt,
        expiresAt: nil, checkState: .failed, detail: "无法构造检查地址", port: domain.port)
    }

    let capture = CertificateTrustCapture(hostname: domain.hostname, port: domain.port)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 8
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let session = URLSession(configuration: configuration, delegate: capture, delegateQueue: nil)
    defer { session.invalidateAndCancel() }

    var request = URLRequest(url: url)
    request.httpMethod = "HEAD"
    request.timeoutInterval = 8
    var requestError: Error?
    do { _ = try await session.data(for: request) } catch { requestError = error }

    if let observed = capture.observed {
      return CertificateSnapshot(
        hostname: domain.hostname, checkedAt: checkedAt, expiresAt: observed.expiresAt,
        checkState: observed.isTrusted ? .trusted : .untrusted,
        detail: observed.isTrusted ? nil : "证书链或域名校验未通过", port: domain.port
      )
    }
    return CertificateSnapshot(
      hostname: domain.hostname, checkedAt: checkedAt, expiresAt: nil,
      checkState: .failed,
      detail: Self.failureDescription(requestError, port: domain.port), port: domain.port
    )
  }

  private static func failureDescription(_ error: Error?, port: Int) -> String {
    guard let error = error as? URLError else { return "未能读取服务器证书" }
    switch error.code {
    case .cannotFindHost: return "找不到域名，请检查拼写或 DNS"
    case .timedOut: return "连接超时，请检查网络或服务器"
    case .notConnectedToInternet, .networkConnectionLost: return "网络不可用，请稍后主动重试"
    case .cannotConnectToHost: return "无法连接服务器的 \(port) 端口"
    default: return "证书检查失败，请检查网络或服务器"
    }
  }
}

private struct ObservedCertificate: Sendable {
  let expiresAt: Date
  let isTrusted: Bool
}

private final class CertificateTrustCapture: NSObject, URLSessionDelegate, URLSessionTaskDelegate,
  @unchecked Sendable
{
  private let hostname: String
  private let port: Int
  private let lock = NSLock()
  private var value: ObservedCertificate?

  init(hostname: String, port: Int) {
    self.hostname = hostname
    self.port = port
  }

  var observed: ObservedCertificate? {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      challenge.protectionSpace.host.caseInsensitiveCompare(hostname) == .orderedSame,
      challenge.protectionSpace.port == port,
      let trust = challenge.protectionSpace.serverTrust
    else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    let isTrusted = SecTrustEvaluateWithError(trust, nil)
    guard
      let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
      let leaf = chain.first,
      let expiresAt = SecCertificateCopyNotValidAfterDate(leaf) as Date?
    else {
      completionHandler(.cancelAuthenticationChallenge, nil)
      return
    }
    lock.lock()
    value = ObservedCertificate(expiresAt: expiresAt, isTrusted: isTrusted)
    lock.unlock()
    completionHandler(.cancelAuthenticationChallenge, nil)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
