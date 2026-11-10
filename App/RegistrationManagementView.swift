import SwiftUI

struct RegistrationManagementView: View {
  @ObservedObject var model: RegistrationDashboardModel
  @ObservedObject var certificates: DashboardModel
  @State private var showingAdd = false
  @State private var removing: RegisteredDomain?
  @State private var search = ""

  var body: some View {
    TimelineView(.periodic(from: .now, by: 3_600)) { context in
      List {
        Section {
          Text("域名注册到期")
            .font(.title2.bold())
          Text("独立监控 \(model.domains.count) 个注册域名 · 不要求部署 HTTPS")
            .foregroundStyle(.secondary)
          Text("宿主运行时约每天查询一次；关闭窗口继续，完全退出后停止。不需要添加 Widget。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        if let error = model.storageError {
          ContentUnavailableView(
            "注册数据无法读取", systemImage: "externaldrive.badge.exclamationmark", description: Text(error)
          )
          Button("修复后重新读取") { Task { await model.load() } }
            .disabled(model.isChecking)
        } else {
          if !certificates.notificationsEnabled {
            HStack {
              Text(certificates.notificationDescription)
              Spacer()
              Button(certificates.notificationDenied ? "检查通知状态" : "开启通知") {
                Task {
                  await model.requestNotifications()
                  await certificates.refreshNotificationStatus()
                }
              }
            }
          }
          if model.domains.isEmpty {
            ContentUnavailableView(
              "还没有注册域名", systemImage: "globe",
              description: Text("点击工具栏“＋”添加 example.com 这类完整注册域名。"))
          } else {
            let domains = visibleDomains(at: context.date)
            if domains.isEmpty {
              ContentUnavailableView.search(text: search)
            }
            ForEach(domains) { domain in
              RegistrationDomainRow(
                domain: domain, snapshot: model.snapshot(for: domain.id), date: context.date
              ) {
                removing = domain
              }
            }
          }
        }
      }
      .listStyle(.inset)
      .searchable(text: $search, prompt: "搜索注册域名")
    }
    .toolbar {
      Button {
        showingAdd = true
      } label: {
        Label("添加注册域名", systemImage: "plus")
      }
      .disabled(model.storageError != nil)
      Button {
        Task { await model.refresh(force: true) }
      } label: {
        Label("检查全部注册域名", systemImage: "arrow.clockwise")
      }
      .disabled(model.storageError != nil || model.isChecking || model.domains.isEmpty)
    }
    .overlay(alignment: .top) {
      if model.isChecking {
        ProgressView("正在查询注册日期…")
          .padding(8)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
          .padding(.top, 4)
      }
    }
    .sheet(isPresented: $showingAdd) { AddRegistrationSheet(model: model) }
    .confirmationDialog(
      "移除注册域名？",
      isPresented: Binding(
        get: { removing != nil }, set: { if !$0 { removing = nil } }
      ), presenting: removing
    ) { domain in
      Button("移除 \(domain.hostname)", role: .destructive) {
        removing = nil
        Task { await model.remove(domain.id) }
      }
      Button("取消", role: .cancel) { removing = nil }
    } message: { _ in
      Text("将移除注册快照及待发注册提醒，不影响 HTTPS 证书监控。")
    }
    .alert(
      "操作未完成",
      isPresented: Binding(
        get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } }
      )
    ) {
      Button("好") { model.actionError = nil }
    } message: {
      Text(model.actionError ?? "")
    }
    .onAppear { model.reload() }
  }

  private func visibleDomains(at date: Date) -> [RegisteredDomain] {
    model.domains.filter { search.isEmpty || $0.hostname.localizedCaseInsensitiveContains(search) }
      .sorted {
        let left = model.snapshot(for: $0.id)?.dates.preferred ?? .distantPast
        let right = model.snapshot(for: $1.id)?.dates.preferred ?? .distantPast
        return left == right ? $0.id < $1.id : left < right
      }
  }
}

private struct AddRegistrationSheet: View {
  @ObservedObject var model: RegistrationDashboardModel
  @Environment(\.dismiss) private var dismiss
  @FocusState private var focused: Bool
  @State private var saving = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("添加注册域名").font(.title2.bold())
      TextField("完整注册域名，例如 example.com", text: $model.input)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onSubmit(add)
        .onChange(of: model.input) { _, _ in model.inputError = nil }
      Text("请输入实际注册的完整域名，例如 example.co.uk；不会自动截取子域名，也不会新增 HTTPS 端点。")
        .font(.caption)
        .foregroundStyle(.secondary)
      if let error = model.inputError { Text(error).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button("添加", action: add)
          .keyboardShortcut(.defaultAction)
          .disabled(saving || model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(24)
    .frame(width: 440)
    .onAppear { focused = true }
  }

  private func add() {
    guard !saving else { return }
    saving = true
    Task {
      if await model.add() { dismiss() }
      saving = false
    }
  }
}
