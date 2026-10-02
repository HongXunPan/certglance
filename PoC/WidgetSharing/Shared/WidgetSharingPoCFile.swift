import Darwin
import Foundation

enum WidgetSharingPoCIdentity {
  static let directoryName = "com.HongXunPan.SSLWidget.WidgetSharingPoC"
  static let requestFilename = "request.txt"
  static let receiptFilename = "receipt.json"
  static let widgetKind = "com.HongXunPan.SSLWidget.WidgetSharingPoC.widget"

  static var currentBuildVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
  }
}

struct WidgetSharingPoCReceipt: Codable {
  let requestMarker: String
  let receiptMarker: String
  let widgetBuildVersion: String?
  let installedAppBuildVersion: String?
  let installedAppReadStatus: String?
  let observedAt: Date?
}

enum WidgetSharingPoCFileError: Error {
  case accountHomeUnavailable
}

enum WidgetSharingPoCFile {
  static func accountHomeURL() throws -> URL {
    guard let account = getpwuid(getuid()), let home = account.pointee.pw_dir else {
      throw WidgetSharingPoCFileError.accountHomeUnavailable
    }
    let path = String(cString: home)
    guard path.hasPrefix("/") else {
      throw WidgetSharingPoCFileError.accountHomeUnavailable
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  static func directoryURL() throws -> URL {
    try accountHomeURL()
      .appendingPathComponent("Library/Application Support", isDirectory: true)
      .appendingPathComponent(WidgetSharingPoCIdentity.directoryName, isDirectory: true)
  }

  static func requestURL() throws -> URL {
    try directoryURL()
      .appendingPathComponent("config", isDirectory: true)
      .appendingPathComponent(WidgetSharingPoCIdentity.requestFilename)
  }

  static func receiptURL() throws -> URL {
    try directoryURL()
      .appendingPathComponent("state", isDirectory: true)
      .appendingPathComponent(WidgetSharingPoCIdentity.receiptFilename)
  }

  static func writeNewRequest() throws -> String {
    let directory = try directoryURL()
    let manager = FileManager.default
    for name in ["", "config", "state"] {
      let target =
        name.isEmpty ? directory : directory.appendingPathComponent(name, isDirectory: true)
      try manager.createDirectory(
        at: target,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
      try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: target.path)
    }

    let marker = String(UUID().uuidString.prefix(8))
    let file = try requestURL()
    try Data(marker.utf8).write(to: file, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    return marker
  }

  static func readRequest() throws -> String {
    try String(contentsOf: requestURL(), encoding: .utf8)
  }

  static func writeReceipt(
    for requestMarker: String, installedAppBuildVersion: String?, installedAppReadStatus: String
  ) throws -> WidgetSharingPoCReceipt {
    let file = try receiptURL()
    let buildVersion = WidgetSharingPoCIdentity.currentBuildVersion
    var receiptMarker = String(UUID().uuidString.prefix(8))
    if FileManager.default.fileExists(atPath: file.path) {
      let existing = try readReceipt()
      if existing.requestMarker == requestMarker,
        existing.widgetBuildVersion == buildVersion
      {
        receiptMarker = existing.receiptMarker
      }
    }
    let receipt = WidgetSharingPoCReceipt(
      requestMarker: requestMarker,
      receiptMarker: receiptMarker,
      widgetBuildVersion: buildVersion,
      installedAppBuildVersion: installedAppBuildVersion,
      installedAppReadStatus: installedAppReadStatus,
      observedAt: .now
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(receipt).write(to: file, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    return receipt
  }

  static func readReceipt() throws -> WidgetSharingPoCReceipt {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(WidgetSharingPoCReceipt.self, from: Data(contentsOf: receiptURL()))
  }
}
