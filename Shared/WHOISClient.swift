import Foundation
import Network

protocol RegistrationWHOISQuerying: Sendable {
  func reset() async
  func lookup(_ hostname: String) async throws -> (RegistrationDates, String)?
}

actor WHOISClient: RegistrationWHOISQuerying {
  private struct Discovery {
    let checkedAt: Date
    let server: String?
    let error: String?
  }
  private var discovered: [String: Discovery] = [:]

  func reset() { discovered = [:] }

  func lookup(_ hostname: String) async throws -> (RegistrationDates, String)? {
    let tld = String(hostname.split(separator: ".").last!)
    if discovered[tld].map({ Date().timeIntervalSince($0.checkedAt) < 24 * 3_600 }) != true {
      do {
        let text = try await WHOISConnection(server: "whois.iana.org", query: tld).run()
        discovered[tld] = Discovery(
          checkedAt: .now, server: WHOISParser.server(in: text), error: nil)
      } catch {
        discovered[tld] = Discovery(checkedAt: .now, server: nil, error: error.localizedDescription)
        throw error
      }
    }
    if let error = discovered[tld]?.error { throw RegistrationLookupError.message(error) }
    guard let server = discovered[tld]?.server else { return nil }
    let text = try await WHOISConnection(server: server, query: hostname).run()
    return (try WHOISParser.dates(in: text, hostname: hostname), "whois://\(server)/\(hostname)")
  }
}

// 所有可变状态仅在专用串行队列访问，取消、超时与网络回调共享一次性完成门。
private final class WHOISConnection: @unchecked Sendable {
  private let connection: NWConnection
  private let query: String
  private let queue = DispatchQueue(label: "com.HongXunPan.CertGlance.whois")
  private var continuation: CheckedContinuation<String, any Error>?
  private var buffer = Data()
  private var finished = false
  private var sent = false

  init(server: String, query: String) {
    connection = NWConnection(host: NWEndpoint.Host(server), port: 43, using: .tcp)
    self.query = query
  }

  func run() async throws -> String {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        queue.async { self.begin(continuation) }
      }
    } onCancel: {
      self.queue.async { self.finish(.failure(CancellationError())) }
    }
  }

  private func begin(_ continuation: CheckedContinuation<String, any Error>) {
    guard !finished else {
      continuation.resume(throwing: CancellationError())
      return
    }
    self.continuation = continuation
    queue.asyncAfter(deadline: .now() + 10) { [self] in
      finish(.failure(RegistrationLookupError.message("WHOIS 连接超时，TCP 43 可能被网络限制。")))
    }
    connection.stateUpdateHandler = { [self] state in
      switch state {
      case .ready:
        guard !sent, !finished else { return }
        sent = true
        connection.send(
          content: Data("\(query)\r\n".utf8),
          completion: .contentProcessed { error in
            if let error { self.finish(.failure(error)) } else { self.receive() }
          })
      case .failed(let error): finish(.failure(error))
      default: break
      }
    }
    connection.start(queue: queue)
  }

  private func receive() {
    guard !finished else { return }
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
      [self] data, _, complete, error in
      if let data { buffer.append(data) }
      guard buffer.count <= 262_144 else {
        finish(.failure(RegistrationLookupError.message("WHOIS 响应过大，已停止读取。")))
        return
      }
      if let error {
        finish(.failure(error))
      } else if complete {
        guard let text = String(data: buffer, encoding: .utf8) else {
          finish(.failure(RegistrationLookupError.message("WHOIS 字符编码无法安全识别。")))
          return
        }
        finish(.success(text))
      } else {
        receive()
      }
    }
  }

  private func finish(_ result: Result<String, any Error>) {
    guard !finished else { return }
    finished = true
    connection.stateUpdateHandler = nil
    connection.cancel()
    continuation?.resume(with: result)
    continuation = nil
  }
}
