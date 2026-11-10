import SwiftUI

@main
struct SSLWidgetApp: App {
  @NSApplicationDelegateAdaptor(ApplicationLifecycleDelegate.self) private var lifecycle

  var body: some Scene {
    Window("CertGlance", id: "main") {
      MonitorWorkspaceView(session: lifecycle.session)
        .frame(minWidth: 560, minHeight: 460)
    }
    .defaultSize(width: 760, height: 640)
    Settings {
      ReminderSettingsView(model: lifecycle.session.certificates)
    }
  }
}
