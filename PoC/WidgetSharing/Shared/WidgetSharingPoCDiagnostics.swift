import CryptoKit
import Foundation

struct WidgetSharingPoCInspection {
  let status: String
  let value: String
  let requestMarker: String
  let receiptMatched: Bool
  let widgetBuildVersion: String?
  let installedAppBuildVersion: String?
  let installedAppReadStatus: String?
  let observedAt: Date?
  let location: String
  let directoryFingerprint: String
  let filePresence: String

  var fullText: String {
    "\(status)：\(value)\n请求标记：\(requestMarker)\n当前进程构建：\(WidgetSharingPoCIdentity.currentBuildVersion) · 回执构建：\(widgetBuildVersion ?? "未提供")\n回执所见安装构建：\(installedAppBuildVersion ?? "未读取") · 读取状态：\(installedAppReadStatus ?? "未提供")\n回执观测时间：\(observedAt?.formatted(date: .abbreviated, time: .standard) ?? "未提供")\n位置：\(location) · 目录标识：\(directoryFingerprint)\n\(filePresence)"
  }

  var versionSummary: String {
    let installed = installedAppBuildVersion ?? (installedAppReadStatus == nil ? "待检查" : "读取失败")
    return "进程 \(WidgetSharingPoCIdentity.currentBuildVersion) · 安装 \(installed)"
  }
}

enum WidgetSharingPoCDiagnostics {
  static func inspect(writeReceipt: Bool = false) -> WidgetSharingPoCInspection {
    do {
      let directory = try WidgetSharingPoCFile.directoryURL()
      let requestFile = try WidgetSharingPoCFile.requestURL()
      let receiptFile = try WidgetSharingPoCFile.receiptURL()
      let fingerprint = SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8))
        .prefix(4).map { String(format: "%02x", $0) }.joined()
      let location = try locationLabel(for: directory)
      func result(
        status: String,
        value: String,
        requestMarker: String = "无",
        receiptMatched: Bool = false,
        widgetBuildVersion: String? = nil,
        installedAppBuildVersion: String? = nil,
        installedAppReadStatus: String? = nil,
        observedAt: Date? = nil
      ) -> WidgetSharingPoCInspection {
        let manager = FileManager.default
        let requestPresence = manager.fileExists(atPath: requestFile.path) ? "存在" : "不存在"
        let receiptPresence = manager.fileExists(atPath: receiptFile.path) ? "存在" : "不存在"
        return WidgetSharingPoCInspection(
          status: status,
          value: value,
          requestMarker: requestMarker,
          receiptMatched: receiptMatched,
          widgetBuildVersion: widgetBuildVersion,
          installedAppBuildVersion: installedAppBuildVersion,
          installedAppReadStatus: installedAppReadStatus,
          observedAt: observedAt,
          location: location,
          directoryFingerprint: fingerprint,
          filePresence: "请求文件：\(requestPresence) · 回执文件：\(receiptPresence)"
        )
      }

      guard FileManager.default.fileExists(atPath: requestFile.path) else {
        return result(status: "尚无请求", value: "等待宿主写入")
      }
      let request: String
      do {
        request = try WidgetSharingPoCFile.readRequest()
      } catch {
        return result(status: "请求读取失败", value: errorCode(error))
      }

      if writeReceipt {
        do {
          let installedApp = WidgetSharingPoCInstalledAppObservation.read()
          let receipt = try WidgetSharingPoCFile.writeReceipt(
            for: request,
            installedAppBuildVersion: installedApp.buildVersion,
            installedAppReadStatus: installedApp.readStatus
          )
          return result(
            status: receipt.installedAppBuildVersion != nil
              && receipt.installedAppBuildVersion != receipt.widgetBuildVersion
              ? "安装与进程版本不一致" : "组件写回成功",
            value: receipt.receiptMarker,
            requestMarker: request, receiptMatched: true,
            widgetBuildVersion: receipt.widgetBuildVersion,
            installedAppBuildVersion: receipt.installedAppBuildVersion,
            installedAppReadStatus: receipt.installedAppReadStatus,
            observedAt: receipt.observedAt
          )
        } catch {
          return result(status: "回执写入失败", value: errorCode(error), requestMarker: request)
        }
      }

      guard FileManager.default.fileExists(atPath: receiptFile.path) else {
        return result(status: "等待组件回执", value: "尚未写回", requestMarker: request)
      }
      do {
        let receipt = try WidgetSharingPoCFile.readReceipt()
        let requestMatched = receipt.requestMarker == request
        let buildMatched =
          receipt.widgetBuildVersion == WidgetSharingPoCIdentity.currentBuildVersion
        return result(
          status: !requestMatched
            ? "回执属于旧请求" : buildMatched ? "回执匹配" : "组件版本不匹配",
          value: receipt.receiptMarker,
          requestMarker: request,
          receiptMatched: requestMatched && buildMatched,
          widgetBuildVersion: receipt.widgetBuildVersion,
          installedAppBuildVersion: receipt.installedAppBuildVersion,
          installedAppReadStatus: receipt.installedAppReadStatus,
          observedAt: receipt.observedAt
        )
      } catch {
        return result(status: "回执读取失败", value: errorCode(error), requestMarker: request)
      }
    } catch {
      return WidgetSharingPoCInspection(
        status: "路径准备失败",
        value: errorCode(error),
        requestMarker: "未知",
        receiptMatched: false,
        widgetBuildVersion: nil,
        installedAppBuildVersion: nil,
        installedAppReadStatus: nil,
        observedAt: nil,
        location: "未知",
        directoryFingerprint: "未知",
        filePresence: "未知"
      )
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
