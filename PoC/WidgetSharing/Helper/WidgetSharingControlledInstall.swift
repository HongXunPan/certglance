import Darwin
import Foundation

private enum ControlledInstallError: LocalizedError {
  case invalidSource
  case invalidBundle
  case invalidBuild
  case appRunning
  case directoryNotWritable
  case differentVolume
  case unexpectedResult

  var errorDescription: String? {
    switch self {
    case .invalidSource:
      "助手不在有效的候选应用包内，或候选包就是已安装应用。"
    case .invalidBundle:
      "候选或已安装应用的身份、结构或签名无效。"
    case .invalidBuild:
      "候选构建号必须高于已安装构建号，且三层构建一致。"
    case .appRunning:
      "PoC 宿主仍在运行，请正常退出后重新预检。"
    case .directoryNotWritable:
      "当前账户不能写入应用程序目录；未尝试提权或覆盖。"
    case .differentVolume:
      "候选暂存包与已安装应用不在同一卷。"
    case .unexpectedResult:
      "系统替换后没有返回固定安装路径。"
    }
  }
}

private struct ControlledInstallContext {
  let sourceURL: URL
  let targetURL: URL
  let sourceBuild: String
  let targetBuild: String
}

enum WidgetSharingControlledInstall {
  private static let appIdentifier = "com.HongXunPan.SSLWidget.WidgetSharingPoC"
  private static let widgetIdentifier = "\(appIdentifier).Widget"
  private static let helperIdentifier = "\(appIdentifier).RepairHelper"
  private static let targetURL = URL(
    fileURLWithPath: "/Applications/WidgetSharingPoC.app", isDirectory: true)

  static func check() throws {
    let context = try preflight()
    print(
      "受控升级预检通过：已安装构建 \(context.targetBuild) → 候选构建 \(context.sourceBuild)；未复制或替换。"
    )
  }

  static func apply() throws {
    let context = try preflight()
    let manager = FileManager.default
    let replacementDirectory = try manager.url(
      for: .itemReplacementDirectory, in: .userDomainMask,
      appropriateFor: context.targetURL, create: true)
    let stagedURL = replacementDirectory.appendingPathComponent(
      "WidgetSharingPoC.app", isDirectory: true)
    var replacementStarted = false
    var completed = false
    defer {
      if completed || (!replacementStarted && manager.fileExists(atPath: context.targetURL.path)) {
        do {
          try manager.removeItem(at: replacementDirectory)
        } catch {
          fputs("升级暂存目录清理失败：\(replacementDirectory.path)\n", stderr)
        }
      } else {
        fputs("升级未确认成功，暂存目录保留供人工检查：\(replacementDirectory.path)\n", stderr)
      }
    }

    _ = try WidgetSharingHelperSecurity.command(
      "/usr/bin/ditto", ["--rsrc", "--extattr", context.sourceURL.path, stagedURL.path])
    guard try verifyApp(stagedURL) == context.sourceBuild else {
      throw ControlledInstallError.invalidBuild
    }
    guard try deviceID(stagedURL) == deviceID(context.targetURL) else {
      throw ControlledInstallError.differentVolume
    }
    let current = try preflight()
    guard current.sourceURL == context.sourceURL,
      current.targetURL == context.targetURL,
      current.sourceBuild == context.sourceBuild,
      current.targetBuild == context.targetBuild
    else {
      throw ControlledInstallError.invalidBuild
    }

    var resultingURL: NSURL?
    replacementStarted = true
    try manager.replaceItem(
      at: context.targetURL, withItemAt: stagedURL,
      backupItemName: nil, options: [], resultingItemURL: &resultingURL)
    guard resultingURL?.path == context.targetURL.path else {
      throw ControlledInstallError.unexpectedResult
    }
    guard try verifyApp(context.targetURL) == context.sourceBuild else {
      throw ControlledInstallError.invalidBuild
    }
    completed = true
    print(
      "受控升级已替换安装包：构建 \(context.targetBuild) → \(context.sourceBuild)；尚未启动宿主或验证桌面组件。"
    )
  }

  private static func preflight() throws -> ControlledInstallContext {
    let helperURL = Bundle.main.bundleURL.standardizedFileURL
    let sourceURL = helperURL.deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
    guard helperURL.lastPathComponent == "WidgetSharingRepairHelper.app",
      helperURL.deletingLastPathComponent().lastPathComponent == "Helpers",
      helperURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        == "Contents",
      sourceURL.lastPathComponent == "WidgetSharingPoC.app",
      sourceURL.resolvingSymlinksInPath() != targetURL.resolvingSymlinksInPath()
    else {
      throw ControlledInstallError.invalidSource
    }

    let sourceBuild = try verifyApp(sourceURL)
    let targetBuild = try verifyApp(targetURL)
    guard let sourceNumber = UInt64(sourceBuild),
      let targetNumber = UInt64(targetBuild),
      sourceNumber > targetNumber
    else {
      throw ControlledInstallError.invalidBuild
    }
    guard Darwin.access(targetURL.deletingLastPathComponent().path, W_OK) == 0 else {
      throw ControlledInstallError.directoryNotWritable
    }

    let executablePaths: Set<String> = [sourceURL, targetURL].map {
      $0.appendingPathComponent("Contents/MacOS/WidgetSharingPoC").path
    }.reduce(into: Set()) { $0.insert($1) }
    let isRunning = try WidgetSharingHelperSecurity.processes().contains {
      $0.userID == getuid() && executablePaths.contains($0.executablePath)
    }
    guard !isRunning else { throw ControlledInstallError.appRunning }
    return ControlledInstallContext(
      sourceURL: sourceURL, targetURL: targetURL,
      sourceBuild: sourceBuild, targetBuild: targetBuild)
  }

  private static func verifyApp(_ appURL: URL) throws -> String {
    let widgetURL = appURL.appendingPathComponent(
      "Contents/PlugIns/WidgetSharingPoCWidget.appex", isDirectory: true)
    let helperURL = appURL.appendingPathComponent(
      "Contents/Helpers/WidgetSharingRepairHelper.app", isDirectory: true)
    let appInfo = try bundleInfo(appURL, expectedIdentifier: appIdentifier)
    let widgetInfo = try bundleInfo(widgetURL, expectedIdentifier: widgetIdentifier)
    let helperInfo = try bundleInfo(helperURL, expectedIdentifier: helperIdentifier)
    guard let build = appInfo["CFBundleVersion"] as? String,
      !build.isEmpty,
      widgetInfo["CFBundleVersion"] as? String == build,
      helperInfo["CFBundleVersion"] as? String == build,
      let extensionInfo = widgetInfo["NSExtension"] as? [String: Any],
      extensionInfo["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
    else {
      throw ControlledInstallError.invalidBuild
    }
    return build
  }

  private static func bundleInfo(
    _ bundleURL: URL, expectedIdentifier: String
  ) throws -> [String: Any] {
    guard isRealDirectory(bundleURL),
      let data = try? Data(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist")),
      let plist = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil),
      let info = plist as? [String: Any],
      info["CFBundleIdentifier"] as? String == expectedIdentifier
    else {
      throw ControlledInstallError.invalidBundle
    }
    try WidgetSharingHelperSecurity.verifySignature(bundleURL)
    return info
  }

  private static func isRealDirectory(_ url: URL) -> Bool {
    var status = stat()
    return Darwin.lstat(url.path, &status) == 0 && (status.st_mode & S_IFMT) == S_IFDIR
  }

  private static func deviceID(_ url: URL) throws -> dev_t {
    var status = stat()
    guard Darwin.lstat(url.path, &status) == 0 else {
      throw ControlledInstallError.differentVolume
    }
    return status.st_dev
  }
}
