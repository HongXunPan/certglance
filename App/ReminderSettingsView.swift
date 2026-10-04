import SwiftUI

struct ReminderSettingsView: View {
  @ObservedObject var model: DashboardModel
  @State private var dayInput = ""
  @State private var inputError: String?
  @State private var isSaving = false

  var body: some View {
    Form {
      Section("到期前提醒") {
        Text("每个 HTTPS 端点分别提醒；同日到期只在看板中合并显示。")
          .foregroundStyle(.secondary)
        if model.reminderPreferences.days.isEmpty {
          Text("当前没有到期前提醒。")
            .foregroundStyle(.secondary)
        }
        ForEach(model.reminderPreferences.days, id: \.self) { day in
          HStack {
            Label("提前 \(day) 天", systemImage: "bell")
            Spacer()
            Button {
              Task { await model.removeReminderDay(day) }
            } label: {
              Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("移除提前 \(day) 天的提醒")
          }
        }
      }
      Section("新增提醒") {
        HStack {
          Text("提前")
          TextField("剩余天数", text: $dayInput)
            .frame(width: 120)
            .onSubmit(addDay)
          Text("天")
          Button("添加") { addDay() }
            .disabled(isSaving)
        }
        if let inputError {
          Text(inputError)
            .foregroundStyle(.red)
        }
        Text("请输入 1 至 3650 的整数；已错过的新增档位不会补发。")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Section("通知状态") {
        Text(model.notificationDescription)
        Text("证书过期提醒独立保留；通知的实际投递时间由 macOS 决定。")
          .font(.caption)
          .foregroundStyle(.secondary)
        if let error = model.reminderSettingsError {
          Text(error)
            .foregroundStyle(.red)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 440, height: 390)
    .task {
      model.refreshReminderPreferences()
      await model.refreshNotificationStatus()
    }
  }

  private func addDay() {
    guard !isSaving else { return }
    let trimmed = dayInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let day = Int(trimmed), (1...ReminderPreferences.maximumDays).contains(day) else {
      inputError = ReminderPreferencesError.invalidDays.localizedDescription
      return
    }
    inputError = nil
    isSaving = true
    Task {
      let saved = await model.addReminderDay(day)
      if saved {
        dayInput = ""
      } else {
        inputError = model.reminderSettingsError
      }
      isSaving = false
    }
  }
}
