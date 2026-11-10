import AppKit
import SwiftUI

@MainActor
private final class UpgradeState: ObservableObject {
  @Published var plan: UpgradePlan?
  @Published var message = "正在核对已安装应用与候选包…"
  @Published var isWorking = true
  @Published var isComplete = false

  func check() {
    isWorking = true
    Task {
      let result = await Task.detached { Result { try UpgradeInstaller.preflight() } }.value
      switch result {
      case .success(let plan):
        self.plan = plan
        self.message = "已安装构建 \(plan.installedBuild) → 候选构建 \(plan.candidateBuild)"
      case .failure(let error):
        self.plan = nil
        self.message = error.localizedDescription
      }
      self.isWorking = false
    }
  }

  func install() {
    guard let plan else { return }
    isWorking = true
    message = "正在验证并安装，请保持 DMG 挂载…"
    Task {
      let result = await Task.detached { Result { try UpgradeInstaller.apply(plan) } }.value
      switch result {
      case .success:
        isComplete = true
        message = "已安装构建 \(plan.candidateBuild)。请检查原桌面小组件是否仍在。"
      case .failure(let error):
        message = error.localizedDescription
      }
      isWorking = false
      self.plan = nil
    }
  }

  func openInstalledApplication() {
    guard NSWorkspace.shared.open(UpgradeInstaller.targetURL) else {
      message = "新版已安装，但未能自动打开。请从“应用程序”手动打开 CertGlance。"
      return
    }
    NSApplication.shared.terminate(nil)
  }
}

private struct UpgradeView: View {
  @StateObject private var state = UpgradeState()

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("升级 CertGlance", systemImage: "checkmark.shield")
        .font(.title2.weight(.semibold))
      Text("仅升级“应用程序”中的 CertGlance；不会主动清除域名或操作小组件。")
        .foregroundStyle(.secondary)
      GroupBox {
        HStack(spacing: 10) {
          if state.isWorking { ProgressView().controlSize(.small) }
          Text(state.message)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .padding(.vertical, 4)
      }
      HStack {
        Button("退出") { NSApplication.shared.terminate(nil) }
          .disabled(state.isWorking)
        Spacer()
        if state.isComplete {
          Button("打开 CertGlance") { state.openInstalledApplication() }
            .buttonStyle(.borderedProminent)
        } else {
          Button("重新检查") { state.check() }
            .disabled(state.isWorking)
          Button("开始升级") { state.install() }
            .buttonStyle(.borderedProminent)
            .disabled(state.isWorking || state.plan == nil)
        }
      }
    }
    .padding(24)
    .frame(width: 500)
    .onAppear { state.check() }
  }
}

@main
struct CertGlanceUpgradeApp: App {
  var body: some Scene {
    Window("升级 CertGlance", id: "upgrade") {
      UpgradeView()
    }
    .windowResizability(.contentSize)
  }
}
