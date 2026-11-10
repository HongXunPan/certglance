#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work="${CERTGLANCE_VISUAL_WORK:-$root/.codex-tmp/certglance-visual-previews}"
case "$work" in
  "$root"/.codex-tmp/*) ;;
  *) printf '预览目录必须位于本仓 .codex-tmp 内。\n' >&2; exit 2 ;;
esac
mkdir -p "$work/module-cache" "$work/clang-cache" "$work/swift-tmp" "$work/output"
cd "$root"

TMPDIR="$work/swift-tmp" xcrun swiftc -swift-version 6 -parse-as-library \
  -module-cache-path "$work/module-cache" \
  -Xcc "-fmodules-cache-path=$work/clang-cache" \
  Shared/DomainModels.swift Shared/CertificateDisplayGrouping.swift \
  Shared/SeverityStyle.swift Shared/CertificateValidityGauge.swift \
  App/DashboardComponents.swift App/EndpointCards.swift App/ExpiryGroupCard.swift \
  Shared/SharedStore.swift Shared/ReminderPreferences.swift \
  Shared/RegistrationModels.swift Shared/RegistrationStore.swift App/RegistrationDomainRow.swift \
  Widget/RegistrationExpiryWidget.swift Tests/RegistrationVisualPreview.swift \
  Widget/WidgetDisplayModel.swift Widget/WidgetSupportingViews.swift \
  Widget/WidgetRiskRow.swift \
  Widget/WidgetLargeOverviewView.swift Widget/SSLExpiryWidgetView.swift \
  Tests/VisualPreview.swift -o "$work/render-visual-previews"

"$work/render-visual-previews" "$work/output"
printf '[完成] 离屏预览：%s\n' "$work/output"
printf '[边界] 原生 Menu／List 外壳与 WidgetKit 实际边距仍须实机复核。\n'
