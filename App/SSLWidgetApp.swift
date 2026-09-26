import SwiftUI

@main
struct SSLWidgetApp: App {
  @StateObject private var model = DashboardModel()

  var body: some Scene {
    WindowGroup("SSL 证书看板") {
      DomainManagementView(model: model)
        .frame(minWidth: 520, minHeight: 410)
    }
    .defaultSize(width: 620, height: 520)
  }
}
