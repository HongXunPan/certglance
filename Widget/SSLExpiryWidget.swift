import SwiftUI
import WidgetKit

@main
struct SSLExpiryWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: CertGlanceIdentity.widgetKind, provider: SSLExpiryProvider()) {
      entry in
      SSLExpiryWidgetView(entry: entry)
    }
    .configurationDisplayName("SSL 证书到期")
    .description("优先显示最需要处理的证书。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}
