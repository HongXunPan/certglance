#!/bin/bash
set -euo pipefail

fail() {
  printf '[失败] %s\n' "$1" >&2
  exit 1
}

[[ "$#" -eq 4 ]] || fail '用法：build-upgrader.sh 候选应用 输出应用 签名指纹 工作目录'
source_app="$1"
output_app="$2"
identity_sha1="$3"
work_dir="$4"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ -d "${source_app}/Contents/PlugIns/SSLExpiryWidget.appex" ]] || fail '候选应用缺少 Widget'
if [[ "${identity_sha1}" == '-' ]]; then
  [[ "${CERTGLANCE_TEST_BUILD:-}" == 1 ]] || fail '仅显式本地测试允许临时签名'
else
  [[ "${identity_sha1}" =~ ^[[:xdigit:]]{40}$ ]] || fail '签名指纹无效'
fi
[[ ! -e "${output_app}" ]] || fail '升级器输出路径已存在'
mkdir -p "${output_app}/Contents/MacOS" "${output_app}/Contents/Resources" "${work_dir}"
cp "${root}/Upgrader/Info.plist" "${output_app}/Contents/Info.plist"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${source_app}/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${source_app}/Contents/Info.plist")"
plutil -replace CFBundleShortVersionString -string "${version}" "${output_app}/Contents/Info.plist"
plutil -replace CFBundleVersion -string "${build}" "${output_app}/Contents/Info.plist"
ditto "${source_app}/Contents/Resources/Assets.car" "${output_app}/Contents/Resources/Assets.car"
ditto -c -k --sequesterRsrc --keepParent "${source_app}" \
  "${output_app}/Contents/Resources/CertGlance.zip"
mkdir -p "${work_dir}/archive-check"
ditto -x -k "${output_app}/Contents/Resources/CertGlance.zip" \
  "${work_dir}/archive-check"
codesign --verify --deep --strict --verbose=2 \
  "${work_dir}/archive-check/CertGlance.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "${work_dir}/archive-check/CertGlance.app/Contents/Info.plist")" == "${build}" ]] ||
  fail '升级器安装包构建号不一致'

sdk="$(xcrun --sdk macosx --show-sdk-path)"
for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 6 -sdk "${sdk}" \
    -target "${arch}-apple-macosx26.0" \
    -module-cache-path "${work_dir}/SwiftModuleCache-${arch}" \
    -Xcc "-fmodules-cache-path=${work_dir}/ClangModuleCache-${arch}" \
    "${root}/Upgrader/UpgradeInstaller.swift" \
    "${root}/Upgrader/WidgetExtensionProcess.swift" \
    "${root}/Upgrader/CertGlanceUpgradeApp.swift" \
    -o "${work_dir}/CertGlanceUpgrade-${arch}"
done
lipo -create "${work_dir}/CertGlanceUpgrade-arm64" \
  "${work_dir}/CertGlanceUpgrade-x86_64" \
  -output "${output_app}/Contents/MacOS/CertGlanceUpgrade"
codesign --force --sign "${identity_sha1}" --options runtime --timestamp=none "${output_app}"
codesign --verify --deep --strict --verbose=2 "${output_app}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${output_app}/Contents/Info.plist")" == \
  "${build}" ]] || fail '升级器构建号不一致'
[[ "$(lipo -archs "${output_app}/Contents/MacOS/CertGlanceUpgrade")" == *arm64* ]] ||
  fail '升级器缺少 arm64 切片'
[[ "$(lipo -archs "${output_app}/Contents/MacOS/CertGlanceUpgrade")" == *x86_64* ]] ||
  fail '升级器缺少 x86_64 切片'
printf '[通过] 双架构独立升级器已生成并完成签名校验\n'
