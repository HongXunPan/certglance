import Darwin
import Foundation

@main
struct UpgradeProcessChecks {
  static func main() throws {
    if CommandLine.arguments.contains("--hold") {
      sleep(120)
      return
    }
    guard CommandLine.arguments.count == 2 else { fatalError("请传入受管临时目录") }
    let executablePath =
      "/Applications/CertGlance.app/Contents/PlugIns/SSLExpiryWidget.appex/Contents/MacOS/SSLExpiryWidget"
    let previous = WidgetExtensionProcessIdentity(
      pid: 123, userID: getuid(), startedAtSeconds: 100,
      startedAtMicroseconds: 10, processName: "SSLExpiryWidget", executablePath: executablePath)
    precondition(
      WidgetExtensionProcess.shouldSignal(
        previous: previous, current: previous, executablePath: executablePath),
      "同一用户、同一旧进程和目标路径才允许结束")
    let reused = WidgetExtensionProcessIdentity(
      pid: 123, userID: getuid(), startedAtSeconds: 101,
      startedAtMicroseconds: 10, processName: "SSLExpiryWidget", executablePath: executablePath)
    precondition(
      !WidgetExtensionProcess.shouldSignal(
        previous: previous, current: reused, executablePath: executablePath),
      "PID 被复用时不能结束新进程")
    let reusedWithinSecond = WidgetExtensionProcessIdentity(
      pid: 123, userID: getuid(), startedAtSeconds: 100,
      startedAtMicroseconds: 11, processName: "SSLExpiryWidget", executablePath: executablePath)
    precondition(
      !WidgetExtensionProcess.shouldSignal(
        previous: previous, current: reusedWithinSecond, executablePath: executablePath),
      "同一秒内 PID 被复用也不能结束新进程")
    let moved = WidgetExtensionProcessIdentity(
      pid: 123, userID: getuid(), startedAtSeconds: 100,
      startedAtMicroseconds: 10, processName: "SSLExpiryWidget",
      executablePath: "/Applications/Other.app/Contents/MacOS/Other")
    precondition(
      !WidgetExtensionProcess.shouldSignal(
        previous: previous, current: moved, executablePath: executablePath),
      "路径变化时不能结束其他应用")
    let otherUser = WidgetExtensionProcessIdentity(
      pid: 123, userID: getuid() + 1, startedAtSeconds: 100,
      startedAtMicroseconds: 10, processName: "SSLExpiryWidget", executablePath: executablePath)
    precondition(
      !WidgetExtensionProcess.shouldSignal(
        previous: otherUser, current: otherUser, executablePath: executablePath),
      "不能结束其他用户进程")
    precondition(
      !WidgetExtensionProcess.shouldSignal(
        previous: previous, current: previous, executablePath: "/Applications/Other.app"),
      "目标路径不一致时不能结束进程")
    let unreadablePath = WidgetExtensionProcessIdentity(
      pid: 123, userID: getuid(), startedAtSeconds: 100,
      startedAtMicroseconds: 10, processName: "SSLExpiryWidget", executablePath: nil)
    precondition(
      WidgetExtensionProcess.shouldSignal(
        previous: previous, current: unreadablePath, executablePath: executablePath),
      "原位替换后路径不可读但进程身份相同，应允许旧进程退出")
    let changedName = WidgetExtensionProcessIdentity(
      pid: 123, userID: getuid(), startedAtSeconds: 100,
      startedAtMicroseconds: 10, processName: "Other", executablePath: nil)
    precondition(
      !WidgetExtensionProcess.shouldSignal(
        previous: previous, current: changedName, executablePath: executablePath),
      "同 PID 执行其他程序时不能结束")

    let empty = WidgetExtensionProcess.terminateCaptured([], executablePath: executablePath)
    precondition(empty.signaledCount == 0 && empty.unresolvedCount == 0, "空列表不能发送信号")

    let currentExecutable = CommandLine.arguments[0]
    let found = try WidgetExtensionProcess.capture(executablePath: currentExecutable)
    precondition(found.contains { $0.pid == getpid() }, "应能读取当前进程身份")
    try verifyReplacement(in: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true))
    print("升级器旧扩展身份检查通过")
  }

  private static func verifyReplacement(in parent: URL) throws {
    let directory = parent.appendingPathComponent("widget-process-replacement", isDirectory: true)
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let oldExecutable = directory.appendingPathComponent("TestWidget")
    let newExecutable = directory.appendingPathComponent("TestWidgetNext")
    let source = URL(fileURLWithPath: CommandLine.arguments[0])
    try manager.copyItem(at: source, to: oldExecutable)
    try manager.copyItem(at: source, to: newExecutable)

    let child = Process()
    child.executableURL = oldExecutable
    child.arguments = ["--hold"]
    try child.run()
    defer {
      if child.isRunning { child.terminate() }
      child.waitUntilExit()
    }
    let captured = try WidgetExtensionProcess.capture(executablePath: oldExecutable.path)
    guard captured.contains(where: { $0.pid == child.processIdentifier }) else {
      throw TestError.message("替换前未识别到测试子进程")
    }
    var resultingURL: NSURL?
    try manager.replaceItem(
      at: oldExecutable, withItemAt: newExecutable,
      backupItemName: nil, options: [], resultingItemURL: &resultingURL)
    guard resultingURL?.path == oldExecutable.path else {
      throw TestError.message("测试可执行文件未完成原位替换")
    }
    let recovery = WidgetExtensionProcess.terminateCaptured(
      captured, executablePath: oldExecutable.path)
    guard recovery.signaledCount == 1, recovery.unresolvedCount == 0 else {
      throw TestError.message(
        "原位替换后未能定点结束旧测试子进程：发送 \(recovery.signaledCount)，未确认 \(recovery.unresolvedCount)")
    }
    child.waitUntilExit()
    guard child.terminationReason == .uncaughtSignal, child.terminationStatus == SIGTERM else {
      throw TestError.message("旧测试子进程未按 SIGTERM 退出")
    }
  }
}

private enum TestError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let value): value
    }
  }
}
