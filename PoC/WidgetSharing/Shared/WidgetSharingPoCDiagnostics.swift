import CryptoKit
import Foundation

enum WidgetSharingPoCDiagnostics {
  static func inspect() -> String {
    do {
      let directory = try WidgetSharingPoCFile.directoryURL()
      let file = directory.appendingPathComponent(WidgetSharingPoCIdentity.filename)
      let fingerprint = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
        .prefix(4).map { String(format: "%02x", $0) }.joined()
      let location = try locationLabel(for: directory)
      let presence = FileManager.default.fileExists(atPath: file.path) ? "存在" : "不存在"
      let summary = "位置：\(location) · 目录标识：\(fingerprint) · 文件：\(presence)"
      do {
        return "\(summary)\n读取成功：\(try WidgetSharingPoCFile.readMarker())"
      } catch {
        return "\(summary)\n读取失败：\(errorCode(error))"
      }
    } catch {
      return "路径准备失败：\(errorCode(error))"
    }
  }

  static func errorCode(_ error: any Error) -> String {
    let nsError = error as NSError
    let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
    let underlyingCode = underlying.map { "\($0.domain)/\($0.code)" } ?? "无"
    return "\(nsError.domain)/\(nsError.code)，底层 \(underlyingCode)"
  }

  private static func locationLabel(for directory: URL) throws -> String {
    let accountHome = try WidgetSharingPoCFile.accountHomeURL().standardizedFileURL.path
    let processHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
      .standardizedFileURL.path
    let path = directory.standardizedFileURL.path
    if path.hasPrefix(accountHome + "/") {
      return accountHome == processHome ? "账户与进程主目录相同" : "账户主目录"
    }
    if path.hasPrefix(processHome + "/") { return "进程容器" }
    return "其他位置"
  }
}
