import SwiftUI

struct DomainManagementView: View {
  @ObservedObject var model: DashboardModel

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        TextField("域名，例如 example.com", text: $model.input)
          .textFieldStyle(.roundedBorder)
          .onSubmit { Task { await model.addDomain() } }
          .accessibilityLabel("要添加的域名")
        Button("添加") { Task { await model.addDomain() } }
          .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
      HStack {
        Label(model.notificationDescription, systemImage: "bell")
          .foregroundStyle(.secondary)
        Spacer()
        Button("开启通知") { Task { await model.requestNotifications() } }
          .disabled(model.storageError != nil)
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
    .task { await model.load() }
  }

  private func domainRow(_ domain: WatchedDomain) -> some View {
    let snapshot = model.snapshot(for: domain.hostname)
    let severity = snapshot?.severity(at: Date()) ?? .unchecked
    return HStack(spacing: 12) {
      Image(systemName: severity.symbol)
        .foregroundStyle(severity.tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(domain.hostname).font(.headline).textSelection(.enabled)
        if let snapshot {
          Text(
            snapshot.detail
              ?? "检查于 \(snapshot.checkedAt.formatted(date: .abbreviated, time: .shortened))"
          )
          .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        } else {
          Text("等待首次检查").font(.caption).foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 8)
      Text(severity.label)
        .font(.callout.weight(.medium))
        .foregroundStyle(severity.tint)
      Button(role: .destructive) {
        Task { await model.removeDomain(domain.hostname) }
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .accessibilityLabel("删除 \(domain.hostname)")
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .contain)
  }
}
