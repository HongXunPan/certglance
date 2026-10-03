import SwiftUI

struct DomainManagementView: View {
  @ObservedObject var model: DashboardModel
  @State private var domainToRemove: String?

  var body: some View {
    VStack(spacing: 0) {
      TimelineView(.periodic(from: .now, by: 3_600)) { context in
        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            heading
            if let storageError = model.storageError {
              ContentUnavailableView(
                "共享数据不可用", systemImage: "externaldrive.badge.exclamationmark",
                description: Text(storageError))
            } else {
              DashboardSummary(
                domains: model.domains, snapshots: model.snapshots, date: context.date)
              inputSection
              if model.domains.isEmpty {
                ContentUnavailableView(
                  "还没有监控端点", systemImage: "checkmark.shield",
                  description: Text("添加域名或粘贴 HTTPS 网址，证书状态会出现在这里及桌面小组件中。")
                )
                .frame(maxWidth: .infinity)
              } else {
                cardGrid(at: context.date)
              }
            }
          }
          .padding(20)
          .frame(maxWidth: 960)
          .frame(maxWidth: .infinity)
        }
      }
      Divider()
      notificationBar
    }
    .toolbar {
      Button {
        Task { await model.refresh() }
      } label: {
        Label("检查全部端点", systemImage: "arrow.clockwise")
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
      "移除这个端点？",
      isPresented: Binding(
        get: { domainToRemove != nil },
        set: { if !$0 { domainToRemove = nil } }
      ),
      presenting: domainToRemove
    ) { id in
      Button("移除 \(id)", role: .destructive) {
        domainToRemove = nil
        Task { await model.removeDomain(id) }
      }
      Button("取消", role: .cancel) { domainToRemove = nil }
    } message: { _ in
      Text("这个端点的检查记录和待发送提醒也会移除。")
    }
    .task { await model.load() }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text("证书总览")
        .font(.system(.largeTitle, design: .rounded, weight: .bold))
      Text("监控 \(model.domains.count) 个 HTTPS 端点 · 优先呈现需要处理的证书")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var inputSection: some View {
    VStack(alignment: .leading, spacing: 9) {
      Text("添加监控")
        .font(.headline)
      HStack(spacing: 10) {
        TextField("域名或 HTTPS 网址", text: $model.input)
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await model.addDomain() } }
          .onChange(of: model.input) { _, _ in model.inputError = nil }
          .accessibilityLabel("要添加的 HTTPS 端点")
        Button("添加") { Task { await model.addDomain() } }
          .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if let error = model.inputError {
        Label(error, systemImage: "exclamationmark.circle")
          .font(.caption)
          .foregroundStyle(.red)
      } else if let endpoint = try? DomainInput.parseEndpoint(model.input) {
        let id = EndpointIdentity.key(hostname: endpoint.hostname, port: endpoint.port)
        Label("将检查 HTTPS · \(id)", systemImage: "link")
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        Text("支持 example.com、example.com:8443 或带路径的 HTTPS 网址。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
  }

  private func cardGrid(at date: Date) -> some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
      ForEach(DashboardOrder.sorted(model.domains, snapshots: model.snapshots, at: date)) {
        domain in
        CertificateDashboardCard(
          domain: domain, snapshot: model.snapshot(for: domain.id), date: date,
          onRemove: { domainToRemove = domain.id })
      }
    }
  }

  private var notificationBar: some View {
    HStack(spacing: 12) {
      Label(model.notificationDescription, systemImage: "bell.badge")
        .foregroundStyle(.secondary)
      Spacer()
      Button("开启通知") { Task { await model.requestNotifications() } }
        .disabled(model.storageError != nil || model.notificationsEnabled)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }
}
