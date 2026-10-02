import Darwin
import Foundation

private enum RepairError: Error {
  case invalidBundle
  case invalidBuild
  case invalidSignature
  case noOutdatedReceipt
  case multipleProcesses
  case processChanged
  case commandFailed
  case signalFailed
}

private enum WidgetSharingRepairHelper {
  static let appIdentifier = "com.HongXunPan.SSLWidget.WidgetSharingPoC"
  static let widgetIdentifier = "\(appIdentifier).Widget"
  static let helperIdentifier = "\(appIdentifier).RepairHelper"
  static let signingSHA1 = "f7b4e6b1573d170587e9139eb1855f90803556a2"

  static func run() throws {
    let helperURL = Bundle.main.bundleURL.standardizedFileURL
    let appURL = helperURL.deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    let widgetURL = appURL.appendingPathComponent(
      "Contents/PlugIns/WidgetSharingPoCWidget.appex", isDirectory: true)
    let executableURL = widgetURL.appendingPathComponent(
      "Contents/MacOS/WidgetSharingPoCWidget")
    let build = WidgetSharingPoCIdentity.currentBuildVersion

    guard helperURL.lastPathComponent == "WidgetSharingRepairHelper.app",
      helperURL.deletingLastPathComponent().lastPathComponent == "Helpers",
      appURL.lastPathComponent == "WidgetSharingPoC.app",
      Bundle.main.bundleIdentifier == helperIdentifier,
      Bundle(url: appURL)?.bundleIdentifier == appIdentifier,
      Bundle(url: widgetURL)?.bundleIdentifier == widgetIdentifier,
      Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String == build,
      Bundle(url: widgetURL)?.object(forInfoDictionaryKey: "CFBundleVersion") as? String == build
    else {
      throw RepairError.invalidBundle
    }
    guard build != "未知" else { throw RepairError.invalidBuild }

    try verifySignature(appURL)
    try verifySignature(widgetURL)
    try verifySignature(helperURL)

    let request = try WidgetSharingPoCFile.readRequest()
    let receipt = try WidgetSharingPoCFile.readReceipt()
    guard receipt.requestMarker == request, receipt.widgetBuildVersion != build else {
      throw RepairError.noOutdatedReceipt
    }

    let processPath = executableURL.standardizedFileURL.path
    let userID = getuid()
    let matchingPIDs = try processes().filter {
      $0.userID == userID && $0.executablePath == processPath
    }.map(\.pid)
    guard matchingPIDs.count <= 1 else { throw RepairError.multipleProcesses }
    guard let pid = matchingPIDs.first else { return }

    let current = try processes().first { $0.pid == pid }
    guard current?.userID == userID, current?.executablePath == processPath else {
      throw RepairError.processChanged
    }
    guard kill(pid, SIGTERM) == 0 else { throw RepairError.signalFailed }
  }

  private static func verifySignature(_ bundleURL: URL) throws {
    _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", bundleURL.path])
    let requirement = try command("/usr/bin/codesign", ["-dr", "-", bundleURL.path])
    let expression = try NSRegularExpression(pattern: "certificate leaf = H\"([[:xdigit:]]{40})\"")
    let range = NSRange(requirement.startIndex..<requirement.endIndex, in: requirement)
    guard let match = expression.firstMatch(in: requirement, range: range),
      let hashRange = Range(match.range(at: 1), in: requirement),
      requirement[hashRange].lowercased() == signingSHA1
    else {
      throw RepairError.invalidSignature
    }
  }

  private static func processes() throws -> [(pid: pid_t, userID: uid_t, executablePath: String)] {
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

  private static func command(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw RepairError.commandFailed }
    return String(decoding: data, as: UTF8.self)
  }
}

do {
  try WidgetSharingRepairHelper.run()
} catch {
  fputs("升级修复助手未处理进程：\(error)\n", stderr)
  exit(1)
}
