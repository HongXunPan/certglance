#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
temp_parent="${root}/.codex-tmp"
mkdir -p "${temp_parent}"
temp="$(mktemp -d "${temp_parent}/certglance-check-$(date +%Y%m%d)-XXXXXX")"
trap 'rm -rf "${temp}"' EXIT
cd "${root}"

printf '[开始] 工程与权限结构\n'
plutil -lint SSLWidget.xcodeproj/project.pbxproj \
  App/Info.plist Widget/Info.plist App/App.entitlements Widget/Widget.entitlements

printf '[开始] Swift 格式\n'
xcrun swift format lint --recursive --strict App Widget Shared Tests scripts

swift_cache=(
  -module-cache-path "${temp}/SwiftModuleCache"
  -Xcc "-fmodules-cache-path=${temp}/ClangModuleCache"
)

printf '[开始] 模型规则\n'
xcrun swiftc -swift-version 6 -parse-as-library "${swift_cache[@]}" \
  Shared/DomainModels.swift Shared/CertificateDisplayGrouping.swift \
  Shared/ReminderPreferences.swift Shared/NotificationPolicy.swift Tests/ModelChecks.swift \
  -o "${temp}/ModelChecks"
"${temp}/ModelChecks"

printf '[开始] Widget 时间线规则\n'
xcrun swiftc -swift-version 6 -parse-as-library "${swift_cache[@]}" \
  Shared/DomainModels.swift Shared/WidgetPlanning.swift Tests/WidgetPlanningChecks.swift \
  -o "${temp}/WidgetPlanningChecks"
"${temp}/WidgetPlanningChecks"

printf '[开始] Widget 展示规则\n'
xcrun swiftc -swift-version 6 -parse-as-library "${swift_cache[@]}" \
  Shared/DomainModels.swift Shared/CertificateDisplayGrouping.swift \
  Widget/WidgetDisplayModel.swift Tests/WidgetDisplayChecks.swift \
  -o "${temp}/WidgetDisplayChecks"
"${temp}/WidgetDisplayChecks"

printf '[开始] 多域名检查队列\n'
xcrun swiftc -swift-version 6 -parse-as-library "${swift_cache[@]}" \
  Shared/DomainModels.swift Shared/DomainCheckQueue.swift Shared/WidgetPlanning.swift \
  Tests/DomainCheckQueueChecks.swift -o "${temp}/DomainCheckQueueChecks"
"${temp}/DomainCheckQueueChecks"

printf '[开始] 文件桥接仓储\n'
xcrun swiftc -swift-version 6 -parse-as-library "${swift_cache[@]}" \
  Shared/DomainModels.swift Shared/ReminderPreferences.swift Shared/SharedStore.swift \
  Tests/StoreChecks.swift \
  -o "${temp}/StoreChecks"
"${temp}/StoreChecks" "${temp}"

printf '[开始] Widget 自动检查排他锁\n'
xcrun swiftc -swift-version 6 -parse-as-library "${swift_cache[@]}" \
  Shared/DomainModels.swift Shared/ReminderPreferences.swift Shared/SharedStore.swift \
  Tests/WidgetRefreshLeaseChecks.swift \
  -o "${temp}/WidgetRefreshLeaseChecks"
"${temp}/WidgetRefreshLeaseChecks" "${temp}/widget-lease"

printf '[通过] 静态和定点规则检查完成；尚未验证签名安装与 WidgetKit 运行态。\n'
