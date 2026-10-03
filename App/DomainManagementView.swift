import SwiftUI

struct DomainManagementView: View {
  @ObservedObject var model: DashboardModel
  @State private var domainToRemove: String?

  var body: some View {
    VStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 8) {
        Text("监控域名")
          .font(.title2.weight(.semibold))
        Text("添加 HTTPS 域名，小组件会优先展示最需要处理的证书。")
          .font(.subheadline)
          .foregroundStyle(.secondary)
        HStack(spacing: 10) {
          TextField("例如 example.com", text: $model.input)
            .textFieldStyle(.roundedBorder)
            .onSubmit { Task { await model.addDomain() } }
            .accessibilityLabel("要添加的域名")
          Button("添加域名") { Task { await model.addDomain() } }
            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        Text("只需填写域名，不含 https://、端口或路径。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding()

      if let storageError = model.storageError {
        ContentUnavailableView(
          "共享数据不可用", systemImage: "externaldrive.badge.exclamationmark",
          description: Text(storageError))
      } else if model.domains.isEmpty {
        ContentUnavailableView(
          "还没有域名", systemImage: "checkmark.shield",
          description: Text("添加域名后，证书到期情况会显示在桌面小组件中。"))
      } else {
        List {
          ForEach(DashboardOrder.sorted(model.domains, snapshots: model.snapshots, at: Date())) {
            domain in
            domainRow(domain)
          }
        }
        .listStyle(.inset)
      }

      Divider()
      HStack(spacing: 12) {
        Label(model.notificationDescription, systemImage: "bell.badge")
          .foregroundStyle(.secondary)
        Spacer()
        Button("开启通知") { Task { await model.requestNotifications() } }
          .disabled(model.storageError != nil || model.notificationsEnabled)
      }
      .padding()
    }
    .toolbar {
      Button {
        Task { await model.refresh() }
      } label: {
        Label("检查全部域名", systemImage: "arrow.clockwise")
      }
      .disabled(model.isChecking || model.domains.isEmpty)
    }
    .overlay(alignment: .top) {
      if model.isChecking {
        ProgressView("正在检查证书…")
          .padding(8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .padding(.top, 4)
      }
    }
    .alert(
      "操作未完成",
      isPresented: Binding(
        get: { model.alertMessage != nil },
        set: { if !$0 { model.alertMessage = nil } }
      )
    ) {
      Button("好") { model.alertMessage = nil }
    } message: {
      Text(model.alertMessage ?? "")
    }
    .confirmationDialog(
      "移除这个域名？",
      isPresented: Binding(
        get: { domainToRemove != nil },
        set: { if !$0 { domainToRemove = nil } }
      ),
      presenting: domainToRemove
    ) { hostname in
      Button("移除 \(hostname)", role: .destructive) {
        domainToRemove = nil
        Task { await model.removeDomain(hostname) }
      }
      Button("取消", role: .cancel) { domainToRemove = nil }
    } message: { _ in
      Text("这个域名的检查记录和待发送提醒也会移除。")
    }
    .task { await model.load() }
  }

  private func domainRow(_ domain: WatchedDomain) -> some View {
    let snapshot = model.snapshot(for: domain.hostname)
    let severity = snapshot?.severity(at: Date()) ?? .unchecked
    return HStack(alignment: .center, spacing: 14) {
      Image(systemName: severity.symbol)
        .font(.title3)
        .foregroundStyle(severity.tint)
        .frame(width: 28)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(domain.hostname).font(.headline).textSelection(.enabled)
        if let snapshot {
          if let detail = snapshot.detail {
            Text(detail)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
            if let expiry = snapshot.expiresAt {
              Text(
                "\(snapshot.checkState == .failed ? "上次已知到期日" : "证书到期日")：\(expiry.formatted(date: .abbreviated, time: .omitted))"
              )
              .font(.caption)
              .foregroundStyle(.secondary)
            }
          } else if let expiry = snapshot.expiresAt {
            Text("到期于 \(expiry.formatted(date: .abbreviated, time: .omitted))")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        } else {
          Text("等待首次检查").font(.subheadline).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 3) {
        Text(severity.label)
          .font(.callout.weight(.semibold))
          .foregroundStyle(severity.tint)
        if let snapshot, snapshot.checkState == .trusted,
          let days = snapshot.daysRemaining(at: Date()), days > 0
        {
          Text("剩余 \(days) 天")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
      }
      Button(role: .destructive) {
        domainToRemove = domain.hostname
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("删除 \(domain.hostname)")
      .help("移除 \(domain.hostname)")
    }
    .padding(.vertical, 8)
    .accessibilityElement(children: .contain)
  }
}
