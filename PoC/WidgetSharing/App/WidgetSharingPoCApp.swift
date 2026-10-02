import SwiftUI
import WidgetKit

@main
struct WidgetSharingPoCApp: App {
  @State private var result = "尚未写入假请求"

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
    }
  }

  @MainActor
  private func writeRequest() {
    do {
      let marker = try WidgetSharingPoCFile.writeNewRequest()
      result = "已写入新请求：\(marker)\n\(WidgetSharingPoCDiagnostics.inspect().fullText)"
      WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharingPoCIdentity.widgetKind)
    } catch {
      result =
        "请求写入失败：\(WidgetSharingPoCDiagnostics.errorCode(error))\n"
        + WidgetSharingPoCDiagnostics.inspect().fullText
    }
  }
}
