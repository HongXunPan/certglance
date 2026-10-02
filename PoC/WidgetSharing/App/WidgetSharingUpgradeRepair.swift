import AppKit
import Foundation

enum WidgetSharingUpgradeObservation {
  case current
  case outdated(String?)
  case pending
}

enum WidgetSharingUpgradeRepairError: Error {
  case invalidHelper
  case helperTimeout
}

enum WidgetSharingUpgradeRepair {
  static func waitForReceipt(
    requestMarker: String,
    expectedBuild: String,
    duration: Duration = .seconds(120)
  ) async -> WidgetSharingUpgradeObservation {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: duration)
    repeat {
      if let receipt = try? WidgetSharingPoCFile.readReceipt(),
        receipt.requestMarker == requestMarker
      {
        return receipt.widgetBuildVersion == expectedBuild
          ? .current : .outdated(receipt.widgetBuildVersion)
      }
      if Task.isCancelled { return .pending }
      try? await Task.sleep(for: .seconds(2))
    } while clock.now < deadline
    return .pending
  }

  @MainActor
  static func launchHelper(expectedBuild: String) async throws {
    let helperURL = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Helpers/WidgetSharingRepairHelper.app", isDirectory: true)
    guard let helperBundle = Bundle(url: helperURL),
      helperBundle.bundleIdentifier
        == "com.HongXunPan.SSLWidget.WidgetSharingPoC.RepairHelper",
      helperBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String == expectedBuild
    else {
      throw WidgetSharingUpgradeRepairError.invalidHelper
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    configuration.addsToRecentItems = false
    configuration.createsNewApplicationInstance = true
    let running = try await NSWorkspace.shared.openApplication(
      at: helperURL, configuration: configuration)
    for _ in 0..<100 {
      if running.isTerminated { return }
      try await Task.sleep(for: .milliseconds(200))
    }
    throw WidgetSharingUpgradeRepairError.helperTimeout
  }
}
