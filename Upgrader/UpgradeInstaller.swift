import AppKit
import Darwin
import Foundation

enum UpgradeError: LocalizedError, Sendable {
  case invalidInstaller
  case notInstalled
  case invalidApplication
  case invalidVersion
  case applicationRunning
  case directoryNotWritable
  case differentVolume
  case unexpectedReplacement
  case commandFailed

  var errorDescription: String? {
    switch self {
    case .invalidInstaller:
      "升级器或内置安装包不完整。请重新下载并核对 DMG。"
    case .notInstalled:
      "“应用程序”中没有 CertGlance。首次安装请将 DMG 中的 CertGlance.app 拖入“应用程序”。"
    case .invalidApplication:
      "已安装应用或候选应用的身份、Widget 结构或签名不匹配；未替换旧版。"
    case .invalidVersion:
      "候选构建必须高于已安装构建，且宿主与 Widget 的构建号一致。"
    case .applicationRunning:
      "CertGlance 仍在运行。请从应用菜单退出后点击“重新检查”。"
    case .directoryNotWritable:
      "当前账户不能写入“应用程序”文件夹；未提权，也未替换旧版。"
    case .differentVolume:
      "升级暂存包与已安装应用不在同一磁盘卷；未替换旧版。"
    case .unexpectedReplacement:
      "系统未确认替换结果。请先检查“应用程序”中的 CertGlance，勿重复覆盖。"
    case .commandFailed:
      "系统解包或签名核验失败；未开始替换旧版。"
    }
  }
}

struct UpgradePlan: Sendable {
  let installedBuild: String
  let candidateBuild: String
}

struct UpgradeOutcome: Sendable {
  let widgetRecovery: WidgetExtensionRecoveryResult
}

enum UpgradeInstaller {
  private static let appIdentifier = "com.HongXunPan.CertGlance"
  private static let widgetIdentifier = "\(appIdentifier).Widget"
  private static let installerIdentifier = "\(appIdentifier).Upgrade"
  private static let signingSHA1 = "f7b4e6b1573d170587e9139eb1855f90803556a2"
  static let targetURL = URL(fileURLWithPath: "/Applications/CertGlance.app", isDirectory: true)
  private static let widgetExecutablePath = targetURL.appendingPathComponent(
    "Contents/PlugIns/SSLExpiryWidget.appex/Contents/MacOS/SSLExpiryWidget"
  ).path

  static func preflight() throws -> UpgradePlan {
    guard Bundle.main.bundleIdentifier == installerIdentifier,
      Bundle.main.url(forResource: "CertGlance", withExtension: "zip") != nil,
      let candidateBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      UInt64(candidateBuild) != nil
    else { throw UpgradeError.invalidInstaller }
    try verifySignature(Bundle.main.bundleURL)
    guard FileManager.default.fileExists(atPath: targetURL.path) else {
      throw UpgradeError.notInstalled
    }
    let installedBuild = try verifyApplication(targetURL)
    guard let installedNumber = UInt64(installedBuild),
      let candidateNumber = UInt64(candidateBuild), candidateNumber > installedNumber
    else { throw UpgradeError.invalidVersion }
    guard Darwin.access(targetURL.deletingLastPathComponent().path, W_OK) == 0 else {
      throw UpgradeError.directoryNotWritable
    }
    guard NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier).isEmpty
    else {
      throw UpgradeError.applicationRunning
    }
    return UpgradePlan(installedBuild: installedBuild, candidateBuild: candidateBuild)
  }

  static func apply(_ plan: UpgradePlan) throws -> UpgradeOutcome {
    let current = try preflight()
    guard current.installedBuild == plan.installedBuild,
      current.candidateBuild == plan.candidateBuild,
      let archiveURL = Bundle.main.url(forResource: "CertGlance", withExtension: "zip")
    else { throw UpgradeError.invalidVersion }

    let manager = FileManager.default
    let replacementDirectory = try manager.url(
      for: .itemReplacementDirectory, in: .userDomainMask,
      appropriateFor: targetURL, create: true)
    let stagedURL = replacementDirectory.appendingPathComponent("CertGlance.app", isDirectory: true)
    var replacementStarted = false
    var completed = false
    defer {
      if completed || !replacementStarted {
        try? manager.removeItem(at: replacementDirectory)
      } else {
        fputs("替换结果不明，暂存目录保留：\(replacementDirectory.path)\n", stderr)
      }
    }

    _ = try command("/usr/bin/ditto", ["-x", "-k", archiveURL.path, replacementDirectory.path])
    guard try verifyApplication(stagedURL) == plan.candidateBuild else {
      throw UpgradeError.invalidVersion
    }
    guard try deviceID(stagedURL) == deviceID(targetURL) else {
      throw UpgradeError.differentVolume
    }
    let rechecked = try preflight()
    guard rechecked.installedBuild == plan.installedBuild,
      rechecked.candidateBuild == plan.candidateBuild
    else { throw UpgradeError.invalidVersion }
    let oldWidgetProcesses = try WidgetExtensionProcess.capture(
      executablePath: widgetExecutablePath)

    var resultingURL: NSURL?
    replacementStarted = true
    do {
      try manager.replaceItem(
        at: targetURL, withItemAt: stagedURL,
        backupItemName: nil, options: [], resultingItemURL: &resultingURL)
      guard resultingURL?.path == targetURL.path,
        try verifyApplication(targetURL) == plan.candidateBuild
      else { throw UpgradeError.unexpectedReplacement }
    } catch {
      throw UpgradeError.unexpectedReplacement
    }
    completed = true
    return UpgradeOutcome(
      widgetRecovery: WidgetExtensionProcess.terminateCaptured(
        oldWidgetProcesses, executablePath: widgetExecutablePath))
  }

  private static func verifyApplication(_ url: URL) throws -> String {
    let widgetURL = url.appendingPathComponent(
      "Contents/PlugIns/SSLExpiryWidget.appex", isDirectory: true)
    let appInfo = try bundleInfo(url, identifier: appIdentifier)
    let widgetInfo = try bundleInfo(widgetURL, identifier: widgetIdentifier)
    guard let appBuild = appInfo["CFBundleVersion"] as? String,
      UInt64(appBuild) != nil,
      widgetInfo["CFBundleVersion"] as? String == appBuild,
      let extensionInfo = widgetInfo["NSExtension"] as? [String: Any],
      extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
    else { throw UpgradeError.invalidVersion }
    return appBuild
  }

  private static func bundleInfo(_ url: URL, identifier: String) throws -> [String: Any] {
    var status = stat()
    guard Darwin.lstat(url.path, &status) == 0,
      (status.st_mode & S_IFMT) == S_IFDIR,
      let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
      let value = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil),
      let info = value as? [String: Any],
      info["CFBundleIdentifier"] as? String == identifier
    else { throw UpgradeError.invalidApplication }
    try verifySignature(url)
    return info
  }

  private static func verifySignature(_ url: URL) throws {
    _ = try command("/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path])
    let requirement = try command("/usr/bin/codesign", ["-dr", "-", url.path])
    guard
      requirement.localizedCaseInsensitiveContains(
        "certificate leaf = H\"\(signingSHA1)\"")
    else { throw UpgradeError.invalidApplication }
  }

  private static func deviceID(_ url: URL) throws -> dev_t {
    var status = stat()
    guard Darwin.lstat(url.path, &status) == 0 else { throw UpgradeError.differentVolume }
    return status.st_dev
  }

  private static func command(_ executable: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    do { try process.run() } catch { throw UpgradeError.commandFailed }
    let result = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw UpgradeError.commandFailed }
    return String(decoding: result, as: UTF8.self)
  }
}
