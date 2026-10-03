import Darwin
import Foundation

private enum RepairError: Error {
  case invalidBundle
  case invalidBuild
  case noOutdatedReceipt
  case multipleProcesses
  case processChanged
  case signalFailed
}

private enum WidgetSharingRepairHelper {
  static let appIdentifier = "com.HongXunPan.SSLWidget.WidgetSharingPoC"
  static let widgetIdentifier = "\(appIdentifier).Widget"
  static let helperIdentifier = "\(appIdentifier).RepairHelper"
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

    try WidgetSharingHelperSecurity.verifySignature(appURL)
    try WidgetSharingHelperSecurity.verifySignature(widgetURL)
    try WidgetSharingHelperSecurity.verifySignature(helperURL)

    let request = try WidgetSharingPoCFile.readRequest()
    let receipt = try WidgetSharingPoCFile.readReceipt()
    guard receipt.requestMarker == request, receipt.widgetBuildVersion != build else {
      throw RepairError.noOutdatedReceipt
    }

    let processPath = executableURL.standardizedFileURL.path
    let userID = getuid()
    let matchingPIDs = try WidgetSharingHelperSecurity.processes().filter {
      $0.userID == userID && $0.executablePath == processPath
    }.map(\.pid)
    guard matchingPIDs.count <= 1 else { throw RepairError.multipleProcesses }
    guard let pid = matchingPIDs.first else { return }

    let current = try WidgetSharingHelperSecurity.processes().first { $0.pid == pid }
    guard current?.userID == userID, current?.executablePath == processPath else {
      throw RepairError.processChanged
    }
    guard kill(pid, SIGTERM) == 0 else { throw RepairError.signalFailed }
  }

}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
  switch arguments {
  case []:
    try WidgetSharingRepairHelper.run()
  case ["--install-check"]:
    try WidgetSharingControlledInstall.check()
  case ["--install-apply"]:
    try WidgetSharingControlledInstall.apply()
  default:
    fputs("用法：WidgetSharingRepairHelper [--install-check | --install-apply]\n", stderr)
    exit(2)
  }
} catch {
  let detail =
    (error as? LocalizedError)?.errorDescription
    ?? "\((error as NSError).domain)/\((error as NSError).code)"
  fputs("升级助手未完成操作：\(detail)\n", stderr)
  exit(1)
}
