#!/bin/bash
set -euo pipefail

fail() {
  printf '[失败] %s\n' "$1" >&2
  exit 1
}

[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] ||
  fail '正式候选签名只允许在 GitHub 托管 Runner 运行'
for name in SSL_WIDGET_SIGNING_P12_BASE64 SSL_WIDGET_SIGNING_P12_PASSWORD SSL_WIDGET_SIGNING_CERT_SHA1; do
  [[ -n "${!name:-}" ]] || fail "缺少签名配置：${name}"
done
expected_sha1="$(printf '%s' "${SSL_WIDGET_SIGNING_CERT_SHA1}" | tr '[:upper:]' '[:lower:]')"
[[ "${expected_sha1}" =~ ^[[:xdigit:]]{40}$ ]] || fail '证书指纹格式无效'
[[ "${expected_sha1}" == f7b4e6b1573d170587e9139eb1855f90803556a2 ]] ||
  fail '签名证书不是项目已验证的专用身份'

for name in xcodebuild xcrun security codesign hdiutil ditto openssl plutil shasum lipo; do
  command -v "${name}" >/dev/null 2>&1 || fail "缺少工具：${name}"
done

umask 077
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
mkdir -p "${root}/.codex-tmp" "${root}/dist"
temp="$(mktemp -d "${root}/.codex-tmp/certglance-package-$(date +%Y%m%d)-XXXXXX")"
derived="${temp}/DerivedData"
app="${derived}/Build/Products/Release/CertGlance.app"
widget="${app}/Contents/PlugIns/SSLExpiryWidget.appex"
keychain="${temp}/signing.keychain-db"
p12="${temp}/signing.p12"
pem="${temp}/signing.pem"
dmg="${root}/dist/CertGlance.dmg"
report="${root}/dist/certglance-verification.txt"
checksum="${root}/dist/SHA256SUMS"
mount="${temp}/mounted-dmg"
staging="${temp}/dmg-root"
keychain_created=0
mounted=0

cleanup() {
  local result=$?
  trap - EXIT
  if [[ "${mounted}" -eq 1 ]]; then
    hdiutil detach "${mount}" -force >/dev/null 2>&1 || true
  fi
  if [[ -f "${temp}/original-keychains.txt" ]]; then
    local original=()
    while IFS= read -r item; do original+=("${item}"); done <"${temp}/original-keychains.txt"
    if ! security list-keychains -d user -s "${original[@]}" >/dev/null 2>&1; then
      printf '[失败] 未能恢复钥匙串搜索列表\n' >&2
      result=1
    fi
  fi
  if [[ "${keychain_created}" -eq 1 ]]; then
    if ! security delete-keychain "${keychain}" >/dev/null 2>&1; then
      printf '[失败] 未能删除临时钥匙串\n' >&2
      result=1
    fi
  fi
  if [[ "${result}" -ne 0 ]]; then
    rm -f "${dmg}" "${report}" "${checksum}"
  fi
  rm -rf "${temp}"
  exit "${result}"
}
trap cleanup EXIT
rm -f "${dmg}" "${report}" "${checksum}"

printf '[开始] 构建双架构 CertGlance\n'
xcodebuild -quiet -project "${root}/SSLWidget.xcodeproj" -scheme SSLWidget \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "${derived}" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO build
[[ -f "${app}/Contents/MacOS/CertGlance" ]] || fail '缺少宿主可执行文件'
[[ -f "${widget}/Contents/MacOS/SSLExpiryWidget" ]] || fail '缺少 Widget 可执行文件'
[[ -f "${app}/Contents/Resources/Assets.car" ]] || fail '缺少应用图标资源'
for binary in "${app}/Contents/MacOS/CertGlance" "${widget}/Contents/MacOS/SSLExpiryWidget"; do
  archs="$(lipo -archs "${binary}")"
  [[ " ${archs} " == *' arm64 '* && " ${archs} " == *' x86_64 '* ]] ||
    fail "缺少双架构切片：${binary}"
done

printf '[开始] 导入项目专用签名身份\n'
security list-keychains -d user |
  sed -e 's/^[[:space:]]*"//' -e 's/"$//' >"${temp}/original-keychains.txt"
printf '%s' "${SSL_WIDGET_SIGNING_P12_BASE64}" | /usr/bin/base64 -D >"${p12}"
keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "${keychain_password}" "${keychain}"
keychain_created=1
security set-keychain-settings -lut 21600 "${keychain}"
security unlock-keychain -p "${keychain_password}" "${keychain}"
original=()
while IFS= read -r item; do original+=("${item}"); done <"${temp}/original-keychains.txt"
security list-keychains -d user -s "${keychain}" "${original[@]}"
security import "${p12}" -k "${keychain}" -P "${SSL_WIDGET_SIGNING_P12_PASSWORD}" \
  -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "${keychain_password}" "${keychain}" >/dev/null
security find-certificate -c 'SSL Widget By HongXunPan' -p "${keychain}" >"${pem}"
openssl x509 -in "${pem}" -noout -checkend 0 >/dev/null || fail '签名证书已过期'
actual_sha1="$(openssl x509 -in "${pem}" -noout -fingerprint -sha1 |
  awk -F= '{print $2}' | tr -d ':' | tr '[:upper:]' '[:lower:]')"
[[ "${actual_sha1}" == "${expected_sha1}" ]] || fail '导入证书的指纹不匹配'

printf '[开始] 配置本次 Runner 的代码签名信任\n'
trust_args=()
if security trust-settings-export -d "${temp}/admin-trust-before.plist" \
  >/dev/null 2>"${temp}/admin-trust-error.txt"; then
  trust_args=(-i "${temp}/admin-trust-before.plist")
elif ! grep -Fq 'No Trust Settings were found' "${temp}/admin-trust-error.txt"; then
  cat "${temp}/admin-trust-error.txt" >&2
  fail '无法读取管理员域原有信任设置'
fi
security add-trusted-cert "${trust_args[@]}" -r trustRoot -p codeSign \
  -o "${temp}/code-signing-trust.plist" "${pem}" >/dev/null
plutil -lint "${temp}/code-signing-trust.plist" >/dev/null || fail '信任设置无效'
sudo -n /usr/bin/perl -e 'alarm 45; exec @ARGV' \
  /usr/bin/security trust-settings-import -d "${temp}/code-signing-trust.plist" ||
  fail '托管 Runner 无法导入代码签名信任'
identities="$(security find-identity -v -p codesigning "${keychain}" |
  grep -F '"SSL Widget By HongXunPan"' || true)"
[[ "$(printf '%s\n' "${identities}" | grep -c . || true)" == 1 ]] ||
  fail '专用代码签名身份不存在或不唯一'
identity_sha1="$(printf '%s\n' "${identities}" | awk '{print $2}')"
[[ "$(printf '%s' "${identity_sha1}" | tr '[:upper:]' '[:lower:]')" == "${expected_sha1}" ]] ||
  fail '可用签名身份指纹不匹配'

printf '[开始] 签名 Widget 与宿主\n'
codesign --force --sign "${identity_sha1}" \
  --identifier com.HongXunPan.CertGlance.Widget \
  --entitlements "${root}/Widget/Widget.entitlements" \
  --options runtime --timestamp=none "${widget}"
codesign --force --sign "${identity_sha1}" \
  --identifier com.HongXunPan.CertGlance \
  --entitlements "${root}/App/App.entitlements" \
  --options runtime --timestamp=none "${app}"
codesign --verify --deep --strict --verbose=2 "${app}"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app}/Contents/Info.plist")" == \
  com.HongXunPan.CertGlance ]] || fail '宿主 Bundle ID 不匹配'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${widget}/Contents/Info.plist")" == \
  com.HongXunPan.CertGlance.Widget ]] || fail 'Widget Bundle ID 不匹配'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app}/Contents/Info.plist")" == \
  "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${widget}/Contents/Info.plist")" ]] ||
  fail '宿主与 Widget 构建号不一致'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "${widget}/Contents/Info.plist")" == \
  com.apple.widgetkit-extension ]] || fail 'Widget 扩展点不匹配'

for bundle in "${app}" "${widget}"; do
  requirement="$(codesign -dr - "${bundle}" 2>&1)"
  grep -Fq "certificate leaf = H\"${expected_sha1}\"" <<<"${requirement}" ||
    fail '签名指定要求未锁定项目证书'
  codesign -dv --verbose=4 "${bundle}" 2>&1 | grep -Fxq 'TeamIdentifier=not set' ||
    fail '自签名候选不应带 Apple Team ID'
done
codesign -d --entitlements :- "${app}" >"${temp}/app-entitlements.plist" 2>/dev/null
codesign -d --entitlements :- "${widget}" >"${temp}/widget-entitlements.plist" 2>/dev/null
for file in "${temp}/app-entitlements.plist" "${temp}/widget-entitlements.plist"; do
  plutil -lint "${file}" >/dev/null || fail '签名权限无法解析'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${file}")" == true ]] ||
    fail '候选未保留 App Sandbox'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "${file}")" == true ]] ||
    fail '候选缺少网络客户端权限'
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "${file}" >/dev/null 2>&1; then
    fail '自签名文件桥接候选不应声明 App Group'
  fi
done
app_access="$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
  "${temp}/app-entitlements.plist")"
widget_config="$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.temporary-exception.files.home-relative-path.read-only:0' \
  "${temp}/widget-entitlements.plist")"
widget_state="$(/usr/libexec/PlistBuddy -c \
  'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' \
  "${temp}/widget-entitlements.plist")"
[[ "${app_access}" == '/Library/Application Support/com.HongXunPan.CertGlance/' &&
  "${widget_config}" == '/Library/Application Support/com.HongXunPan.CertGlance/config/' &&
  "${widget_state}" == '/Library/Application Support/com.HongXunPan.CertGlance/state/' ]] ||
  fail '签名产物的文件桥接权限不匹配'
for scope in \
  "${temp}/app-entitlements.plist:com.apple.security.temporary-exception.files.home-relative-path.read-write" \
  "${temp}/widget-entitlements.plist:com.apple.security.temporary-exception.files.home-relative-path.read-only" \
  "${temp}/widget-entitlements.plist:com.apple.security.temporary-exception.files.home-relative-path.read-write"; do
  file="${scope%%:*}"
  key="${scope#*:}"
  if /usr/libexec/PlistBuddy -c "Print :${key}:1" "${file}" >/dev/null 2>&1; then
    fail '签名产物包含额外文件例外目录'
  fi
done

printf '[开始] 制作非公证 DMG\n'
mkdir -p "${staging}" "${mount}"
ditto "${app}" "${staging}/CertGlance.app"
ln -s /Applications "${staging}/Applications"
hdiutil create -ov -volname CertGlance -srcfolder "${staging}" -format UDZO "${dmg}"
codesign --force --sign "${identity_sha1}" --timestamp=none "${dmg}"
codesign --verify --verbose=2 "${dmg}"
hdiutil attach -readonly -nobrowse -mountpoint "${mount}" "${dmg}"
mounted=1
codesign --verify --deep --strict --verbose=2 "${mount}/CertGlance.app"
[[ -d "${mount}/CertGlance.app/Contents/PlugIns/SSLExpiryWidget.appex" ]] ||
  fail 'DMG 内缺少 Widget 扩展'
hdiutil detach "${mount}"
mounted=0
(cd "${root}/dist" && shasum -a 256 CertGlance.dmg >SHA256SUMS)

cat >"${report}" <<EOF
验证对象：CertGlance 正式功能候选
源码提交：${GITHUB_SHA:-未知}
宿主 Bundle ID：com.HongXunPan.CertGlance
Widget Bundle ID：com.HongXunPan.CertGlance.Widget
版本：$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app}/Contents/Info.plist")
构建：$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app}/Contents/Info.plist")
架构：arm64、x86_64
签名证书：SSL Widget By HongXunPan
叶证书 SHA-1 前 12 位：${expected_sha1:0:12}
共享目录：~/Library/Application Support/com.HongXunPan.CertGlance/
权限：宿主根目录读写；Widget 仅 config/ 只读、state/ 读写；保留沙盒与网络客户端权限
静态结果：双架构、嵌入扩展、签名、文件权限、DMG 内签名与 SHA-256 已核验
未验证：新安装后的真实 TLS 检查、WidgetKit 时间线、跨进程文件桥接、系统通知授权和投递；Finder 覆盖升级不支持
EOF
printf '[通过] 正式候选 DMG、校验和和静态报告位于 dist/\n'
