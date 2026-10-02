import Foundation

struct WidgetSharingPoCInstalledAppObservation {
  let buildVersion: String?
  let readStatus: String

  static func read() -> Self {
    let infoURL = URL(
      fileURLWithPath: "/Applications/WidgetSharingPoC.app/Contents/Info.plist")
    do {
      let data = try Data(contentsOf: infoURL)
      guard
        let info = try PropertyListSerialization.propertyList(
          from: data, options: [], format: nil) as? [String: Any]
      else {
        return Self(buildVersion: nil, readStatus: "plist 格式无效")
      }
      guard
        info["CFBundleIdentifier"] as? String
          == "com.HongXunPan.SSLWidget.WidgetSharingPoC"
      else {
        return Self(buildVersion: nil, readStatus: "包身份不匹配")
      }
      guard let build = info["CFBundleVersion"] as? String, !build.isEmpty else {
        return Self(buildVersion: nil, readStatus: "缺少构建号")
      }
      return Self(buildVersion: build, readStatus: "已读取")
    } catch {
      let detail = error as NSError
      return Self(buildVersion: nil, readStatus: "\(detail.domain)/\(detail.code)")
    }
  }
}
