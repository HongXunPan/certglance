import SwiftUI
import WidgetKit

@main
struct WidgetSharingPoCApp: App {
  @State private var result = "尚未写入假数据"

  var body: some Scene {
    WindowGroup("SSL 小组件共享验证") {
      VStack(alignment: .leading, spacing: 16) {
        Text("WidgetKit 专用文件验证")
          .font(.headline)
        Text(result)
          .textSelection(.enabled)
        Button("写入新假标记") {
          writeMarker()
        }
      }
      .padding(24)
      .frame(minWidth: 380)
    }
  }

  @MainActor
  private func writeMarker() {
    do {
      let marker = try WidgetSharingPoCFile.writeNewMarker()
      result = "写入标记：\(marker)\n\(WidgetSharingPoCDiagnostics.inspect())"
      WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharingPoCIdentity.widgetKind)
    } catch {
      result =
        "写入失败：\(WidgetSharingPoCDiagnostics.errorCode(error))\n"
        + WidgetSharingPoCDiagnostics.inspect()
    }
  }
}
