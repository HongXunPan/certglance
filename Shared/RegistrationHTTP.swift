import Foundation

protocol RegistrationFetching: Sendable {
  func get(_ url: URL) async throws -> (Data, URL)
}

struct RegistrationHTTPClient: RegistrationFetching {
  func get(_ url: URL) async throws -> (Data, URL) {
    guard Self.isPublicHTTPS(url) else {
      throw RegistrationLookupError.message("查询服务地址不是有效的公共 HTTPS 地址。")
    }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    configuration.httpShouldSetCookies = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let session = URLSession(
      configuration: configuration, delegate: RegistrationRedirectGuard(), delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    var request = URLRequest(url: url)
    request.setValue("application/rdap+json, application/json", forHTTPHeaderField: "Accept")
    request.setValue("CertGlance/0.1.1", forHTTPHeaderField: "User-Agent")
    let (bytes, response) = try await session.bytes(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw RegistrationLookupError.message("查询服务未返回有效 HTTP 响应。")
    }
    guard response.statusCode == 200 else {
      throw RegistrationLookupError.http(response.statusCode)
    }
    let maximumSize = 1_048_576
    guard response.expectedContentLength <= maximumSize else {
      throw RegistrationLookupError.message("查询响应过大，已停止读取。")
    }
    var data = Data()
    for try await byte in bytes {
      guard data.count < maximumSize else {
        throw RegistrationLookupError.message("查询响应过大，已停止读取。")
      }
      data.append(byte)
    }
    return (data, response.url ?? url)
  }

  static func isPublicHTTPS(_ url: URL) -> Bool {
    guard url.scheme == "https", url.user == nil, url.password == nil,
      url.port == nil || url.port == 443, let host = url.host,
      (try? RegistrationInput.parse(host)) == host.lowercased()
    else { return false }
    return true
  }
}

private final class RegistrationRedirectGuard: NSObject, URLSessionTaskDelegate,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var redirects = 0

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    lock.lock()
    redirects += 1
    let allowed = redirects <= 3 && request.url.map(RegistrationHTTPClient.isPublicHTTPS) == true
    lock.unlock()
    completionHandler(allowed ? request : nil)
  }
}

actor RDAPDirectory {
  private struct Bootstrap: Decodable { let services: [[[String]]] }
  private let http: any RegistrationFetching
  private var loadedAt: Date?
  private var services: [String: URL] = [:]
  private var failure: String?

  init(http: any RegistrationFetching = RegistrationHTTPClient()) { self.http = http }

  func reset() {
    loadedAt = nil
    failure = nil
    services = [:]
  }

  func service(for tld: String) async throws -> URL? {
    if loadedAt.map({ Date().timeIntervalSince($0) < 24 * 3_600 }) != true {
      loadedAt = .now
      do {
        let url = URL(string: "https://data.iana.org/rdap/dns.json")!
        let (data, _) = try await http.get(url)
        let decoded = try JSONDecoder().decode(Bootstrap.self, from: data)
        guard !decoded.services.isEmpty else {
          throw RegistrationLookupError.message("IANA 引导表为空，未继续查询。")
        }
        var discovered: [String: URL] = [:]
        for entry in decoded.services where entry.count == 2 {
          guard
            let service = entry[1].compactMap(URL.init(string:)).first(where: {
              RegistrationHTTPClient.isPublicHTTPS($0)
            })
          else { continue }
          for suffix in entry[0] { discovered[suffix] = service }
        }
        services = discovered
        failure = nil
      } catch {
        failure = "IANA 服务发现失败：\(error.localizedDescription)"
        throw error
      }
    }
    if let failure { throw RegistrationLookupError.message(failure) }
    return services[tld]
  }
}
