import Darwin
import Foundation

enum WidgetSharingPoCIdentity {
  static let directoryName = "com.HongXunPan.SSLWidget.WidgetSharingPoC"
  static let filename = "probe.txt"
  static let widgetKind = "com.HongXunPan.SSLWidget.WidgetSharingPoC.widget"
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

  static func writeNewMarker() throws -> String {
    let directory = try directoryURL()
    let manager = FileManager.default
    try manager.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

    let marker = String(UUID().uuidString.prefix(8))
    let file = directory.appendingPathComponent(WidgetSharingPoCIdentity.filename)
    try Data(marker.utf8).write(to: file, options: .atomic)
    try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    return marker
  }

  static func readMarker() throws -> String {
    let file = try directoryURL().appendingPathComponent(WidgetSharingPoCIdentity.filename)
    return try String(contentsOf: file, encoding: .utf8)
  }
}
