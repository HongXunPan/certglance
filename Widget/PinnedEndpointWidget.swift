import AppIntents
import SwiftUI
import WidgetKit

struct MonitoredEndpointOptions: DynamicOptionsProvider {
  func results() async throws -> [String] {
    let store = try FileSnapshotStore(createIfNeeded: false)
    return try store.domains().map(\.id).sorted()
  }
}

struct PinnedEndpointConfiguration: WidgetConfigurationIntent {
  static let title: LocalizedStringResource = "固定证书端点"
  static let description = IntentDescription("为这一份小组件选择一个监控端点。")

  @Parameter(title: "监控端点", optionsProvider: MonitoredEndpointOptions())
  var endpointID: String?
}

struct PinnedEndpointProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> SSLExpiryEntry {
    WidgetTimelineSource.placeholder(selection: .pinned("example.com"))
  }

  func snapshot(
    for configuration: PinnedEndpointConfiguration, in context: Context
  ) async -> SSLExpiryEntry {
    WidgetTimelineSource.cachedEntry(selection: .pinned(configuration.endpointID))
  }

  func timeline(
    for configuration: PinnedEndpointConfiguration, in context: Context
  ) async -> Timeline<SSLExpiryEntry> {
    await WidgetTimelineSource.timeline(selection: .pinned(configuration.endpointID))
  }
}

struct PinnedEndpointWidget: Widget {
  var body: some WidgetConfiguration {
    AppIntentConfiguration(
      kind: CertGlanceIdentity.pinnedWidgetKind,
      intent: PinnedEndpointConfiguration.self,
      provider: PinnedEndpointProvider()
    ) { entry in
      SSLExpiryWidgetView(entry: entry)
    }
    .configurationDisplayName("固定证书端点")
    .description("为每份小组件分别选择要关注的证书。")
    .supportedFamilies([.systemSmall])
  }
}
