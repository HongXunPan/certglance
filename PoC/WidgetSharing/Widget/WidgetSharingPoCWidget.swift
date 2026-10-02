import SwiftUI
import WidgetKit

private struct WidgetSharingPoCEntry: TimelineEntry {
  let date: Date
  let result: String
}

private struct WidgetSharingPoCProvider: TimelineProvider {
  func placeholder(in context: Context) -> WidgetSharingPoCEntry {
    WidgetSharingPoCEntry(date: .now, result: "等待宿主写入假数据")
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (WidgetSharingPoCEntry) -> Void
  ) {
    completion(makeEntry())
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<WidgetSharingPoCEntry>) -> Void
  ) {
    let entry = makeEntry()
    completion(
      Timeline(entries: [entry], policy: .after(entry.date.addingTimeInterval(15 * 60)))
    )
  }

  private func makeEntry() -> WidgetSharingPoCEntry {
    WidgetSharingPoCEntry(date: .now, result: WidgetSharingPoCDiagnostics.inspect())
  }
}

private struct WidgetSharingPoCView: View {
  let entry: WidgetSharingPoCEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label("SSL 共享 PoC", systemImage: "lock.shield")
        .font(.headline)
      Text(entry.result)
        .font(.caption2)
        .lineLimit(5)
      Spacer(minLength: 0)
      Text("仅假数据 · 版本 1")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding()
    .containerBackground(.background, for: .widget)
  }
}

@main
struct WidgetSharingPoCWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(
      kind: WidgetSharingPoCIdentity.widgetKind,
      provider: WidgetSharingPoCProvider()
    ) { entry in
      WidgetSharingPoCView(entry: entry)
    }
    .configurationDisplayName("SSL 共享验证")
    .description("验证自签名小组件能否读取宿主写入的假数据。")
    .supportedFamilies([.systemSmall])
  }
}
