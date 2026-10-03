import SwiftUI

struct DomainManagementView: View {
  @ObservedObject var model: DashboardModel
  @State private var domainToRemove: String?
  @State private var isShowingAddSheet = false

  var body: some View {
    TimelineView(.periodic(from: .now, by: 3_600)) { context in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          heading
          if let storageError = model.storageError {
            VStack(spacing: 12) {
              ContentUnavailableView(
                "共享数据不可用", systemImage: "externaldrive.badge.exclamationmark",
                description: Text(storageError))
              Button("修复后重新读取") { Task { await model.load() } }
                .disabled(model.isChecking)
            }
          } else if model.domains.isEmpty {
            ContentUnavailableView(
              "还没有监控端点", systemImage: "checkmark.shield",
              description: Text("使用工具栏“＋”添加域名或粘贴 HTTPS 网址。")
            )
            .frame(maxWidth: .infinity)
          } else {
            VStack(alignment: .leading, spacing: 18) {
              if let message = model.lastActionMessage {
                HStack(spacing: 10) {
                  Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                  Spacer(minLength: 0)
                  Button("关闭") { model.dismissActionMessage() }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
              }
              DashboardSummary(
                domains: model.domains, snapshots: model.snapshots, date: context.date)
              if !model.notificationsEnabled {
                notificationCallout
              }
              cardGrid(at: context.date)
            }
          }
        }
        .padding(20)
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity)
      }
    }
    .toolbar {
      Button {
        isShowingAddSheet = true
      } label: {
        Label("添加端点", systemImage: "plus")
      }
      .disabled(model.storageError != nil)

      Button {
        Task { await model.refresh() }
      } label: {
        Label("检查全部端点", systemImage: "arrow.clockwise")
      }
      .disabled(model.storageError != nil || model.isChecking || model.domains.isEmpty)
    }
    .sheet(isPresented: $isShowingAddSheet) {
      AddEndpointSheet(model: model)
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

  private func cardGrid(at date: Date) -> some View {
    let ordered = DashboardOrder.sorted(model.domains, snapshots: model.snapshots, at: date)
    return VStack(alignment: .leading, spacing: 14) {
      if let focus = ordered.first {
        Text("优先关注")
          .font(.headline)
        CertificateFocusCard(
          domain: focus, snapshot: model.snapshot(for: focus.id), date: date,
          onRemove: { domainToRemove = focus.id })
      }
      if ordered.count > 1 {
        Text("其他端点")
          .font(.headline)
          .padding(.top, 4)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
          ForEach(Array(ordered.dropFirst())) { domain in
            CertificateCompactCard(
              domain: domain, snapshot: model.snapshot(for: domain.id), date: date,
              onRemove: { domainToRemove = domain.id })
          }
        }
      }
    }
  }

  private var notificationCallout: some View {
    HStack(spacing: 12) {
      Label(model.notificationDescription, systemImage: "bell.badge")
        .foregroundStyle(.secondary)
      Spacer()
      Button(model.notificationDenied ? "检查通知状态" : "开启通知") {
        Task { await model.requestNotifications() }
      }
    }
    .padding(12)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
  }
}
