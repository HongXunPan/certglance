#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${root}"

printf '[开始] PoC 工程与权限结构\n'
plutil -lint \
  PoC/WidgetSharing/WidgetSharingPoC.xcodeproj/project.pbxproj \
  PoC/WidgetSharing/App/Info.plist \
  PoC/WidgetSharing/Helper/Info.plist \
  PoC/WidgetSharing/Widget/Info.plist \
  PoC/WidgetSharing/App/App.entitlements \
  PoC/WidgetSharing/Widget/Widget.entitlements

printf '[开始] PoC Swift 格式\n'
xcrun swift format lint --recursive --strict \
  PoC/WidgetSharing/App \
  PoC/WidgetSharing/Helper \
  PoC/WidgetSharing/Widget \
  PoC/WidgetSharing/Shared

printf '[通过] PoC 结构与格式检查完成；尚未验证签名安装与 WidgetKit 运行态。\n'
