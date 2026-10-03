import SwiftUI

@main
struct SSLWidgetApp: App {
  @StateObject private var model = DashboardModel()

  var body: some Scene {
    Window("CertGlance", id: "main") {
      DomainManagementView(model: model)
        .frame(minWidth: 520, minHeight: 410)
    }
    .defaultSize(width: 620, height: 520)
  }
}
