import SwiftUI

struct MonitorWorkspaceView: View {
  @ObservedObject var session: ApplicationSession
  @State private var selection = 0

  var body: some View {
    VStack(spacing: 0) {
      Picker("监控类型", selection: $selection) {
        Text("TLS 证书").tag(0)
        Text("域名注册").tag(1)
      }
      .pickerStyle(.segmented)
      .frame(maxWidth: 320)
      .padding()
      Divider()
      if selection == 0 {
        DomainManagementView(model: session.certificates)
      } else {
        RegistrationManagementView(model: session.registrations, certificates: session.certificates)
      }
    }
    .onAppear {
      session.certificates.reloadStoredData()
      session.registrations.reload()
    }
  }
}
