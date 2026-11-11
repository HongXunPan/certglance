import Darwin
import Foundation

struct WidgetExtensionProcessIdentity: Equatable, Sendable {
  let pid: pid_t
  let userID: uid_t
  let startedAtSeconds: UInt64
  let startedAtMicroseconds: UInt64
  let processName: String
  let executablePath: String?
}

struct WidgetExtensionRecoveryResult: Sendable {
  let signaledCount: Int
  let unresolvedCount: Int
}

enum WidgetExtensionProcessError: LocalizedError {
  case inspectionUnavailable

  var errorDescription: String? {
    switch self {
    case .inspectionUnavailable:
      "无法确认当前小组件进程；未开始替换旧版。请稍后重新检查。"
    }
  }
}

enum WidgetExtensionProcess {
  static func capture(executablePath: String) throws -> [WidgetExtensionProcessIdentity] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0, estimate < Int32.max / Int32(MemoryLayout<pid_t>.size) - 256 else {
      throw WidgetExtensionProcessError.inspectionUnavailable
    }
    var pids = [pid_t](repeating: 0, count: Int(estimate) + 256)
    let count = pids.withUnsafeMutableBufferPointer {
      proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
    }
    guard count > 0, count < pids.count else {
      throw WidgetExtensionProcessError.inspectionUnavailable
    }
    return pids.prefix(Int(count)).compactMap { inspect($0) }.filter {
      $0.userID == getuid() && $0.executablePath == executablePath
    }
  }

  static func terminateCaptured(
    _ captured: [WidgetExtensionProcessIdentity], executablePath: String
  ) -> WidgetExtensionRecoveryResult {
    var signaledCount = 0
    var unresolvedCount = 0
    for previous in captured {
      guard let current = inspect(previous.pid) else {
        // 进程可能已自行退出；若 PID 仍存在但无法读取身份，保留显式提示。
        if kill(previous.pid, 0) == 0 || errno != ESRCH { unresolvedCount += 1 }
        continue
      }
      guard shouldSignal(previous: previous, current: current, executablePath: executablePath)
      else { continue }
      if kill(previous.pid, SIGTERM) == 0 {
        signaledCount += 1
      } else if errno != ESRCH {
        unresolvedCount += 1
      }
    }
    return WidgetExtensionRecoveryResult(
      signaledCount: signaledCount, unresolvedCount: unresolvedCount)
  }

  static func shouldSignal(
    previous: WidgetExtensionProcessIdentity, current: WidgetExtensionProcessIdentity,
    executablePath: String
  ) -> Bool {
    previous.executablePath == executablePath && previous.userID == getuid()
      && current.pid == previous.pid && current.userID == previous.userID
      && current.startedAtSeconds == previous.startedAtSeconds
      && current.startedAtMicroseconds == previous.startedAtMicroseconds
      && current.processName == previous.processName
      && (current.executablePath == executablePath || current.executablePath == nil)
  }

  private static func inspect(_ pid: pid_t) -> WidgetExtensionProcessIdentity? {
    guard pid > 0 else { return nil }
    var info = proc_bsdinfo()
    let infoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, infoSize) == infoSize else {
      return nil
    }
    let processName = withUnsafeBytes(of: info.pbi_comm) {
      String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
    var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = path.withUnsafeMutableBufferPointer {
      proc_pidpath(pid, $0.baseAddress, UInt32($0.count))
    }
    let executablePath: String?
    if length > 0, let end = path.firstIndex(of: 0) {
      executablePath = String(
        decoding: path[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    } else {
      // 原位替换后旧可执行文件的路径可能不可读，BSD 身份仍可用于核对同一进程。
      executablePath = nil
    }
    return WidgetExtensionProcessIdentity(
      pid: pid, userID: info.pbi_uid,
      startedAtSeconds: info.pbi_start_tvsec,
      startedAtMicroseconds: info.pbi_start_tvusec,
      processName: processName, executablePath: executablePath)
  }
}
