import SwiftUI
import WidgetKit

@main
struct WidgetSharingPoCApp: App {
  @AppStorage("widgetSharingPoCLastCheckedBuild") private var lastCheckedBuild = ""
  @AppStorage("widgetSharingPoCLastRepairAttemptBuild") private var lastRepairAttemptBuild = ""
  @State private var result = "尚未写入假请求"
  @State private var didCheckAtLaunch = false
  @State private var upgradeIssue: String?
  @State private var isChecking = false

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
        if let upgradeIssue {
          Text(upgradeIssue)
            .foregroundStyle(.orange)
          Button("重新检查升级") {
            Task { await startUpgradeCheck(manual: true) }
          }
          .disabled(isChecking)
        }
      }
      .padding(24)
      .frame(minWidth: 420)
      .task { await checkAtLaunch() }
    }
  }

  @MainActor
  private func checkAtLaunch() async {
    guard !didCheckAtLaunch else { return }
    didCheckAtLaunch = true
    let currentBuild = WidgetSharingPoCIdentity.currentBuildVersion
    guard lastCheckedBuild != currentBuild else {
      result = WidgetSharingPoCDiagnostics.inspect().fullText
      if lastRepairAttemptBuild != currentBuild,
        let request = try? WidgetSharingPoCFile.readRequest(),
        let receipt = try? WidgetSharingPoCFile.readReceipt(),
        receipt.requestMarker == request,
        receipt.widgetBuildVersion != currentBuild
      {
        await repairOutdatedWidget(for: request, build: currentBuild)
      }
      return
    }
    await startUpgradeCheck(manual: false)
  }

  @MainActor
  private func startUpgradeCheck(manual: Bool) async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    upgradeIssue = nil
    let currentBuild = WidgetSharingPoCIdentity.currentBuildVersion
    let extensionURL = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/PlugIns/WidgetSharingPoCWidget.appex", isDirectory: true)
    let embeddedBuild =
      Bundle(url: extensionURL)?
      .object(forInfoDictionaryKey: "CFBundleVersion") as? String
    guard embeddedBuild == currentBuild else {
      upgradeIssue = "宿主与包内组件构建不一致，无法自动修复；请重新安装完整应用。"
      result = "升级检查失败：宿主构建 \(currentBuild)，包内组件构建 \(embeddedBuild ?? "未找到")。"
      return
    }
    guard
      let marker = writeRequest(
        source: manual ? "手动升级检查（构建 \(currentBuild)）" : "启动升级检查（构建 \(currentBuild)）"
      )
    else {
      upgradeIssue = "请求写入失败；原有数据未删除。请检查目录权限后重试。"
      return
    }
    lastCheckedBuild = currentBuild
    let observation = await WidgetSharingUpgradeRepair.waitForReceipt(
      requestMarker: marker, expectedBuild: currentBuild)
    switch observation {
    case .current:
      result = "组件已使用构建 \(currentBuild)。\n" + WidgetSharingPoCDiagnostics.inspect().fullText
    case .outdated:
      if manual || lastRepairAttemptBuild != currentBuild {
        await repairOutdatedWidget(for: marker, build: currentBuild)
      } else {
        upgradeIssue = "本次升级已尝试自动修复，但组件仍在运行旧版本。可手动重新检查。"
      }
    case .pending:
      upgradeIssue = "系统尚未返回这次请求的组件回执，暂不能判断是否需要修复；可稍后重新检查。"
    }
  }

  @MainActor
  private func repairOutdatedWidget(for marker: String, build: String) async {
    guard let currentRequest = try? WidgetSharingPoCFile.readRequest(),
      let receipt = try? WidgetSharingPoCFile.readReceipt(),
      currentRequest == marker,
      receipt.requestMarker == marker,
      receipt.widgetBuildVersion != build
    else {
      upgradeIssue = "请求或回执已变化，未启动修复助手；请重新检查。"
      return
    }
    lastRepairAttemptBuild = build
    result =
      "检测到同一请求仍由旧版组件处理，正在自动修复。\n"
      + WidgetSharingPoCDiagnostics.inspect().fullText
    do {
      try await WidgetSharingUpgradeRepair.launchHelper(expectedBuild: build)
    } catch {
      upgradeIssue = "自动修复助手未能完成：\(WidgetSharingPoCDiagnostics.errorCode(error))。可重新检查，或稍后再试。"
      return
    }
    guard let freshMarker = writeRequest(source: "自动修复后复核（构建 \(build)）") else {
      upgradeIssue = "修复助手已运行，但新请求写入失败；可重新检查。"
      return
    }
    let observation = await WidgetSharingUpgradeRepair.waitForReceipt(
      requestMarker: freshMarker, expectedBuild: build)
    switch observation {
    case .current:
      upgradeIssue = nil
      result = "组件已使用构建 \(build)。\n" + WidgetSharingPoCDiagnostics.inspect().fullText
    case .outdated(let oldBuild):
      upgradeIssue = "新请求仍由旧版组件处理（回执构建 \(oldBuild ?? "未提供")）；没有再次自动处理进程。"
    case .pending:
      upgradeIssue = "修复助手已运行，但系统尚未返回新请求的回执；可稍后重新检查。"
    }
  }

  @MainActor
  @discardableResult
  private func writeRequest(source: String = "手动写入") -> String? {
    do {
      let marker = try WidgetSharingPoCFile.writeNewRequest()
      result =
        "\(source)：已写入新请求 \(marker)；已请求系统刷新组件。\n"
        + WidgetSharingPoCDiagnostics.inspect().fullText
      WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharingPoCIdentity.widgetKind)
      return marker
    } catch {
      result =
        "请求写入失败：\(WidgetSharingPoCDiagnostics.errorCode(error))\n"
        + WidgetSharingPoCDiagnostics.inspect().fullText
      return nil
    }
  }
}
