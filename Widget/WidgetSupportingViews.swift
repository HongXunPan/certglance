import SwiftUI

struct WidgetFreshnessFooter: View {
  let entry: SSLExpiryEntry
  let snapshot: CertificateSnapshot?

  @ViewBuilder
  var body: some View {
    if entry.errorMessage != nil {
      Label("更新失败", systemImage: "exclamationmark.triangle")
        .accessibilityHint("打开应用查看并主动重试")
    } else if entry.reminderErrorMessage != nil {
      Label("提醒异常", systemImage: "bell.slash")
        .accessibilityHint("证书数据已更新，请打开应用查看提醒状态")
    } else if let snapshot, snapshot.checkState == .failed {
      if let successfulAt = snapshot.lastSuccessfulCheckAt {
        Text("最近成功 \(successfulAt.formatted(date: .abbreviated, time: .omitted))")
      } else {
        Text("尚无成功检查")
      }
    } else if let snapshot, entry.date.timeIntervalSince(snapshot.checkedAt) >= 86_400 {
      Text("数据待更新 · 上次检查 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .omitted))")
    }
  }
}

struct WidgetEmptyState: View {
  let title: String
  let detail: String
  let symbol: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Spacer(minLength: 0)
      Image(systemName: symbol)
        .font(.title2)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
      Text(title).font(.headline)
      Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
      Spacer(minLength: 0)
    }
  }
}
