import Darwin
import Foundation

enum WidgetSharingHelperSecurityError: LocalizedError {
  case invalidSignature
  case commandFailed

  var errorDescription: String? {
    switch self {
    case .invalidSignature:
      "签名身份与项目专用证书不匹配。"
    case .commandFailed:
      "系统核验命令执行失败。"
    }
  }
}

enum WidgetSharingHelperSecurity {
  static let signingSHA1 = "f7b4e6b1573d170587e9139eb1855f90803556a2"

  static func verifySignature(_ bundleURL: URL) throws {
    _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundleURL.path])
    let requirement = try command("/usr/bin/codesign", ["-dr", "-", bundleURL.path])
    let expression = try NSRegularExpression(pattern: "certificate leaf = H\"([[:xdigit:]]{40})\"")
    let range = NSRange(requirement.startIndex..<requirement.endIndex, in: requirement)
    guard let match = expression.firstMatch(in: requirement, range: range),
      let hashRange = Range(match.range(at: 1), in: requirement),
      requirement[hashRange].lowercased() == signingSHA1
    else {
      throw WidgetSharingHelperSecurityError.invalidSignature
    }
  }

  static func processes() throws -> [(pid: pid_t, userID: uid_t, executablePath: String)] {
    let output = try command("/bin/ps", ["-axo", "pid=,uid=,comm="])
    return output.split(separator: "\n").compactMap { line in
      let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
      guard fields.count == 3,
        let pid = pid_t(fields[0]),
        let userID = uid_t(fields[1])
      else { return nil }
      return (pid: pid, userID: userID, executablePath: String(fields[2]))
    }
  }

  static func command(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw WidgetSharingHelperSecurityError.commandFailed
    }
    return String(decoding: data, as: UTF8.self)
  }
}
