import SwiftUI

struct AddEndpointSheet: View {
  @Environment(\.dismiss) private var dismiss
  @ObservedObject var model: DashboardModel
  @FocusState private var inputFocused: Bool
  @State private var isSubmitting = false

  private var trimmedInput: String {
    model.input.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      Label("添加 HTTPS 端点", systemImage: "plus.circle.fill")
        .font(.title2.weight(.semibold))

      VStack(alignment: .leading, spacing: 8) {
        Text("域名或网址")
          .font(.headline)
        TextField("example.com 或 https://example.com/path", text: $model.input)
          .textFieldStyle(.roundedBorder)
          .focused($inputFocused)
          .onSubmit { Task { await submit() } }
          .onChange(of: model.input) { _, _ in model.inputError = nil }
          .accessibilityLabel("要添加的 HTTPS 端点")

        if let error = model.inputError {
          Label(error, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityAddTraits(.updatesFrequently)
        } else if let endpoint = try? DomainInput.parseEndpoint(model.input) {
          let id = EndpointIdentity.key(hostname: endpoint.hostname, port: endpoint.port)
          Label("将监控 HTTPS · \(id)", systemImage: "link")
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
          Text("可粘贴带路径的网址；自定义端口请使用 HTTPS 网址或域名:端口。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }

      HStack {
        Spacer()
        Button("取消") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("添加端点") { Task { await submit() } }
          .keyboardShortcut(.defaultAction)
          .disabled(trimmedInput.isEmpty || isSubmitting)
      }
    }
    .padding(24)
    .frame(width: 460)
    .onAppear { inputFocused = true }
  }

  private func submit() async {
    guard !trimmedInput.isEmpty, !isSubmitting else { return }
    isSubmitting = true
    defer { isSubmitting = false }
    if await model.addDomain() {
      dismiss()
    } else {
      inputFocused = true
    }
  }
}
