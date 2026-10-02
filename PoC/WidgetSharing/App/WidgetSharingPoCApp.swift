import SwiftUI
import WidgetKit

@main
struct WidgetSharingPoCApp: App {
  @AppStorage("widgetSharingPoCLastCheckedBuild") private var lastCheckedBuild = ""
  @State private var result = "尚未写入假请求"
  @State private var didCheckAtLaunch = false

  var body: some Scene {
    WindowGroup("SSL 小组件共享验证") {
      VStack(alignment: .leading, spacing: 16) {
        Text("WidgetKit 专用文件验证")
          .font(.headline)
        Text(result)
          .textSelection(.enabled)
        HStack {
          Button("写入新假请求") {
            writeRequest()
          }
          Button("读取组件回执") {
            result = WidgetSharingPoCDiagnostics.inspect().fullText
          }
        }
      }
      .padding(24)
      .frame(minWidth: 420)
      .task { checkAtLaunch() }
    }
  }

  @MainActor
  private func checkAtLaunch() {
    guard !didCheckAtLaunch else { return }
    didCheckAtLaunch = true
    let currentBuild = WidgetSharingPoCIdentity.currentBuildVersion
    guard lastCheckedBuild != currentBuild else {
      result = WidgetSharingPoCDiagnostics.inspect().fullText
      return
    }
    lastCheckedBuild = currentBuild

    let extensionURL = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/PlugIns/WidgetSharingPoCWidget.appex", isDirectory: true)
    let embeddedBuild =
      Bundle(url: extensionURL)?
      .object(forInfoDictionaryKey: "CFBundleVersion") as? String
    guard embeddedBuild == currentBuild else {
      result = "启动检查失败：宿主构建 \(currentBuild)，包内组件构建 \(embeddedBuild ?? "未找到")。"
      return
    }
    writeRequest(source: "启动升级检查（构建 \(currentBuild)）")
  }

  @MainActor
  private func writeRequest(source: String = "手动写入") {
    do {
      let marker = try WidgetSharingPoCFile.writeNewRequest()
      result =
        "\(source)：已写入新请求 \(marker)；已请求系统刷新组件。\n"
        + WidgetSharingPoCDiagnostics.inspect().fullText
      WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharingPoCIdentity.widgetKind)
    } catch {
      result =
        "请求写入失败：\(WidgetSharingPoCDiagnostics.errorCode(error))\n"
        + WidgetSharingPoCDiagnostics.inspect().fullText
    }
  }
}
