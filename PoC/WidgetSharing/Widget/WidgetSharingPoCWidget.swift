import SwiftUI
import WidgetKit

private struct WidgetSharingPoCEntry: TimelineEntry {
  let date: Date
  let inspection: WidgetSharingPoCInspection
}

private struct WidgetSharingPoCProvider: TimelineProvider {
  func placeholder(in context: Context) -> WidgetSharingPoCEntry {
    WidgetSharingPoCEntry(
      date: .now,
      inspection: WidgetSharingPoCInspection(
        status: "等待宿主写入",
        value: "尚无假标记",
        readSucceeded: false,
        location: "未知",
        directoryFingerprint: "未知",
        filePresence: "未知"
      )
    )
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
    WidgetSharingPoCEntry(date: .now, inspection: WidgetSharingPoCDiagnostics.inspect())
  }
}

private struct WidgetSharingPoCView: View {
  let entry: WidgetSharingPoCEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Label("SSL 共享", systemImage: "lock.shield")
        .font(.caption.weight(.semibold))
      Text(entry.inspection.status)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(entry.inspection.value)
        .font(
          entry.inspection.readSucceeded
            ? .system(.title3, design: .monospaced).weight(.semibold) : .caption2
        )
        .lineLimit(entry.inspection.readSucceeded ? 1 : 2)
        .minimumScaleFactor(0.75)
      Text("位置：\(entry.inspection.location)")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Text("目录：\(entry.inspection.directoryFingerprint)")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 0)
      Text("仅假数据 · 版本 2")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .padding()
    .containerBackground(.background, for: .widget)
    .accessibilityElement(children: .combine)
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
