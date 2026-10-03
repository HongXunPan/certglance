import SwiftUI

@main
struct SSLWidgetApp: App {
  @StateObject private var model = DashboardModel()

  var body: some Scene {
    Window("CertGlance", id: "main") {
      DomainManagementView(model: model)
        .frame(minWidth: 560, minHeight: 460)
    }
    .defaultSize(width: 760, height: 640)
  }
}
