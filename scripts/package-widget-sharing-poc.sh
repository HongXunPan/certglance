#!/bin/bash
set -euo pipefail

fail() {
  printf '[失败] %s\n' "$1" >&2
  exit 1
}

diagnostic_without_helper="${WIDGET_SHARING_DIAGNOSTIC_WITHOUT_HELPER:-false}"
[[ "${diagnostic_without_helper}" == true || "${diagnostic_without_helper}" == false ]] ||
  fail '诊断开关必须是 true 或 false'

[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == 'github-hosted' ]] ||
  fail '签名打包仅允许在 GitHub 托管 Runner 运行'

for name in SSL_WIDGET_SIGNING_P12_BASE64 SSL_WIDGET_SIGNING_P12_PASSWORD SSL_WIDGET_SIGNING_CERT_SHA1; do
  [[ -n "${!name:-}" ]] || fail "缺少签名配置：${name}"
done
[[ "${SSL_WIDGET_SIGNING_CERT_SHA1}" =~ ^[[:xdigit:]]{40}$ ]] ||
  fail '证书 SHA-1 必须是 40 位十六进制字符串'
helper_signing_sha1='f7b4e6b1573d170587e9139eb1855f90803556a2'
[[ "$(printf '%s' "${SSL_WIDGET_SIGNING_CERT_SHA1}" | tr '[:upper:]' '[:lower:]')" == "${helper_signing_sha1}" ]] ||
  fail '签名证书与升级修复助手锁定的项目专用证书不一致'

for command_name in xcodebuild xcrun security codesign hdiutil ditto openssl plutil shasum; do
  command -v "${command_name}" >/dev/null 2>&1 || fail "缺少命令：${command_name}"
done
[[ -x /usr/libexec/PlistBuddy ]] || fail '找不到系统 PlistBuddy'
[[ -x /usr/bin/sudo && -x /usr/bin/perl ]] || fail '缺少非交互签名所需的系统命令'

umask 077
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work_parent="${project_root}/.codex-tmp"
output_directory="${project_root}/dist"
mkdir -p "${work_parent}" "${output_directory}"
work_directory="$(mktemp -d "${work_parent}/widget-sharing-signing-$(date +%Y%m%d)-XXXXXX")"
derived_data="${work_directory}/DerivedData"
app_path="${derived_data}/Build/Products/Release/WidgetSharingPoC.app"
widget_path="${app_path}/Contents/PlugIns/WidgetSharingPoCWidget.appex"
helper_path="${app_path}/Contents/Helpers/WidgetSharingRepairHelper.app"
keychain_path="${work_directory}/signing.keychain-db"
certificate_path="${work_directory}/signing.p12"
certificate_pem_path="${work_directory}/signing.pem"
admin_trust_before_path="${work_directory}/admin-trust-before.plist"
admin_trust_error_path="${work_directory}/admin-trust-export.err"
trust_settings_path="${work_directory}/code-signing-trust.plist"
original_keychains_path="${work_directory}/original-keychains.txt"
staging_directory="${work_directory}/dmg-root"
mount_point="${work_directory}/mounted-dmg"
dmg_path="${output_directory}/widget-sharing-poc.dmg"
report_path="${output_directory}/widget-sharing-poc-verification.txt"
checksum_path="${output_directory}/SHA256SUMS"
signing_identity='SSL Widget By HongXunPan'
app_identifier='com.HongXunPan.SSLWidget.WidgetSharingPoC'
widget_identifier="${app_identifier}.Widget"
helper_identifier="${app_identifier}.RepairHelper"
shared_path='/Library/Application Support/com.HongXunPan.SSLWidget.WidgetSharingPoC/'
config_path="${shared_path}config/"
state_path="${shared_path}state/"
mounted=0
keychain_created=0

cleanup() {
  local result=$?
  trap - EXIT
  if [[ "${mounted}" -eq 1 ]]; then
    hdiutil detach "${mount_point}" -force >/dev/null 2>&1 || true
  fi
  if [[ -f "${original_keychains_path}" ]]; then
    local original_keychains=()
    while IFS= read -r keychain; do
      original_keychains+=("${keychain}")
    done <"${original_keychains_path}"
    if ! security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1; then
      printf '[失败] 未能恢复钥匙串搜索列表\n' >&2
      result=1
    fi
  fi
  if [[ "${keychain_created}" -eq 1 ]]; then
    if ! security delete-keychain "${keychain_path}" >/dev/null 2>&1; then
      printf '[失败] 未能删除临时钥匙串\n' >&2
      result=1
    fi
  fi
  if [[ "${result}" -ne 0 ]]; then
    rm -f "${dmg_path}" "${report_path}" "${checksum_path}"
  fi
  rm -rf "${work_directory}"
  exit "${result}"
}
trap cleanup EXIT

rm -f "${dmg_path}" "${report_path}" "${checksum_path}"

printf '[开始] 无签名构建独立 PoC\n'
xcodebuild -quiet \
  -project "${project_root}/PoC/WidgetSharing/WidgetSharingPoC.xcodeproj" \
  -scheme WidgetSharingPoC -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "${derived_data}" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
[[ -f "${app_path}/Contents/MacOS/WidgetSharingPoC" ]] || fail '缺少宿主可执行文件'
[[ -f "${widget_path}/Contents/MacOS/WidgetSharingPoCWidget" ]] ||
  fail '缺少嵌入的 Widget 可执行文件'
[[ -f "${helper_path}/Contents/MacOS/WidgetSharingRepairHelper" ]] ||
  fail '缺少嵌入的升级修复助手可执行文件'
if [[ "${diagnostic_without_helper}" == true ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")" == 8 ]] ||
    fail '无助手诊断仅允许构建 8，避免未来误用'
  [[ -d "${helper_path}" && ! -L "${helper_path}" ]] || fail '诊断候选的助手包路径无效'
  rm -r "${helper_path}"
  rmdir "${app_path}/Contents/Helpers" || fail '诊断候选的助手目录含有非预期文件'
  [[ ! -e "${helper_path}" && ! -L "${helper_path}" ]] || fail '诊断候选仍包含助手包'
  printf '[诊断] 已从生成的 App 中移除嵌入助手；不改动宿主与 Widget 源码\n'
fi

printf '[开始] 导入 SSL Widget 专用签名身份\n'
security list-keychains -d user |
  sed -e 's/^[[:space:]]*"//' -e 's/"$//' >"${original_keychains_path}"
printf '%s' "${SSL_WIDGET_SIGNING_P12_BASE64}" | /usr/bin/base64 -D >"${certificate_path}"
keychain_password="$(openssl rand -hex 24)"
security create-keychain -p "${keychain_password}" "${keychain_path}"
keychain_created=1
security set-keychain-settings -lut 21600 "${keychain_path}"
security unlock-keychain -p "${keychain_password}" "${keychain_path}"

original_keychains=()
while IFS= read -r keychain; do
  original_keychains+=("${keychain}")
done <"${original_keychains_path}"
security list-keychains -d user -s "${keychain_path}" "${original_keychains[@]}"
security import "${certificate_path}" -k "${keychain_path}" \
  -P "${SSL_WIDGET_SIGNING_P12_PASSWORD}" \
  -T /usr/bin/codesign -T /usr/bin/security
printf '[通过] 已导入专用签名身份\n'
printf '[开始] 配置临时钥匙串签名访问\n'
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "${keychain_password}" "${keychain_path}" >/dev/null
printf '[通过] 临时钥匙串签名访问已配置\n'
printf '[开始] 导出并检查签名证书\n'
security find-certificate -c "${signing_identity}" -p "${keychain_path}" \
  >"${certificate_pem_path}"
openssl x509 -in "${certificate_pem_path}" -noout -checkend 0 >/dev/null ||
  fail '签名证书已过期或无法解析'
expected_sha1="$(printf '%s' "${SSL_WIDGET_SIGNING_CERT_SHA1}" | tr '[:lower:]' '[:upper:]')"
imported_sha1="$(openssl x509 -in "${certificate_pem_path}" -noout -fingerprint -sha1 |
  awk -F= '{print $2}' | tr -d ':' | tr '[:lower:]' '[:upper:]')"
[[ "${imported_sha1}" == "${expected_sha1}" ]] ||
  fail '导入证书的指纹与仓库固定配置不一致'
printf '[通过] 签名证书可解析且未过期\n'
printf '[开始] 准备仅限代码签名的管理员域信任设置\n'
trust_file_args=()
if security trust-settings-export -d "${admin_trust_before_path}" \
  >/dev/null 2>"${admin_trust_error_path}"; then
  trust_file_args=(-i "${admin_trust_before_path}")
elif grep -Fq 'No Trust Settings were found' "${admin_trust_error_path}"; then
  printf '[说明] 管理员域原本没有自定义信任设置\n'
else
  cat "${admin_trust_error_path}" >&2
  fail '无法安全读取管理员域原有信任设置'
fi
security add-trusted-cert "${trust_file_args[@]}" -r trustRoot -p codeSign \
  -o "${trust_settings_path}" "${certificate_pem_path}" >/dev/null
plutil -lint "${trust_settings_path}" >/dev/null || fail '代码签名信任设置文件无效'
printf '[开始] 在本次托管 Runner 导入管理员域信任设置\n'
if ! sudo -n /usr/bin/perl -e 'alarm 45; exec @ARGV' \
  /usr/bin/security trust-settings-import -d "${trust_settings_path}"; then
  fail '管理员域信任设置导入失败或超过 45 秒'
fi
# 托管 Runner 在作业结束后销毁，不修改本机或其他作业的信任设置。
printf '[通过] 本次 Runner 的代码签名信任已设置\n'

printf '[开始] 校验唯一签名身份与指纹\n'
identity_lines="$(security find-identity -v -p codesigning "${keychain_path}" |
  grep -F "\"${signing_identity}\"" || true)"
[[ "$(printf '%s\n' "${identity_lines}" | grep -c . || true)" == 1 ]] ||
  fail '专用签名身份不存在或不唯一'
certificate_sha1="$(printf '%s\n' "${identity_lines}" | awk '{print $2}')"
[[ "${certificate_sha1}" == "${expected_sha1}" ]] ||
  fail '证书指纹与仓库固定配置不一致'
printf '[通过] 签名身份与固定指纹一致\n'

printf '[开始] 先签 Widget，再签宿主 App\n'
codesign --force --sign "${certificate_sha1}" \
  --identifier "${widget_identifier}" \
  --entitlements "${project_root}/PoC/WidgetSharing/Widget/Widget.entitlements" \
  --options runtime --timestamp=none "${widget_path}"
if [[ "${diagnostic_without_helper}" == false ]]; then
  codesign --force --sign "${certificate_sha1}" \
    --identifier "${helper_identifier}" \
    --options runtime --timestamp=none "${helper_path}"
fi
codesign --force --sign "${certificate_sha1}" \
  --identifier "${app_identifier}" \
  --entitlements "${project_root}/PoC/WidgetSharing/App/App.entitlements" \
  --options runtime --timestamp=none "${app_path}"
codesign --verify --deep --strict --verbose=2 "${app_path}"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${app_path}/Contents/Info.plist")" == "${app_identifier}" ]] ||
  fail '宿主 Bundle ID 不匹配'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${widget_path}/Contents/Info.plist")" == "${widget_identifier}" ]] ||
  fail 'Widget Bundle ID 不匹配'
embedded_bundles=("${widget_path}")
if [[ "${diagnostic_without_helper}" == false ]]; then
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${helper_path}/Contents/Info.plist")" == "${helper_identifier}" ]] ||
    fail '升级修复助手 Bundle ID 不匹配'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :LSBackgroundOnly' "${helper_path}/Contents/Info.plist")" == true ]] ||
    fail '升级修复助手必须为后台应用'
  embedded_bundles+=("${helper_path}")
fi
for bundle in "${embedded_bundles[@]}"; do
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${bundle}/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${app_path}/Contents/Info.plist")" ]] ||
    fail '嵌入组件与宿主构建号不一致'
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "${widget_path}/Contents/Info.plist")" == 'com.apple.widgetkit-extension' ]] ||
  fail 'Widget 扩展点不匹配'

codesign -d --entitlements :- "${app_path}" >"${work_directory}/signed-app-entitlements.plist" 2>/dev/null
codesign -d --entitlements :- "${widget_path}" >"${work_directory}/signed-widget-entitlements.plist" 2>/dev/null
for entitlement_file in "${work_directory}/signed-app-entitlements.plist" "${work_directory}/signed-widget-entitlements.plist"; do
  plutil -lint "${entitlement_file}" >/dev/null || fail '签名权限声明无法解析'
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${entitlement_file}")" == true ]] ||
    fail '签名产物未保留 App Sandbox'
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "${entitlement_file}" >/dev/null 2>&1; then
    fail '文件桥接 PoC 不应声明 App Group'
  fi
done
if [[ "${diagnostic_without_helper}" == false ]]; then
  if codesign -d --entitlements :- "${helper_path}" >"${work_directory}/signed-helper-entitlements.plist" 2>/dev/null; then
    if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "${work_directory}/signed-helper-entitlements.plist" >/dev/null 2>&1; then
      fail '独立修复助手不能继承宿主沙盒'
    fi
  fi
fi
app_access="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' "${work_directory}/signed-app-entitlements.plist")"
widget_config_access="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.files.home-relative-path.read-only:0' "${work_directory}/signed-widget-entitlements.plist")"
widget_state_access="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.files.home-relative-path.read-write:0' "${work_directory}/signed-widget-entitlements.plist")"
[[ "${app_access}" == "${shared_path}" && "${widget_config_access}" == "${config_path}" && "${widget_state_access}" == "${state_path}" ]] ||
  fail '签名产物的宿主、Widget 请求和回执目录权限不匹配'
for scope in \
  "${work_directory}/signed-app-entitlements.plist:com.apple.security.temporary-exception.files.home-relative-path.read-write" \
  "${work_directory}/signed-widget-entitlements.plist:com.apple.security.temporary-exception.files.home-relative-path.read-only" \
  "${work_directory}/signed-widget-entitlements.plist:com.apple.security.temporary-exception.files.home-relative-path.read-write"; do
  entitlement_file="${scope%%:*}"
  entitlement_key="${scope#*:}"
  if /usr/libexec/PlistBuddy -c "Print :${entitlement_key}:1" "${entitlement_file}" >/dev/null 2>&1; then
    fail '签名产物包含额外文件例外目录'
  fi
done
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.temporary-exception.files.home-relative-path.read-only' "${work_directory}/signed-app-entitlements.plist" >/dev/null 2>&1; then
  fail '宿主签名产物包含冗余只读文件例外'
fi

signed_bundles=("${app_path}" "${embedded_bundles[@]}")
for signed_bundle in "${signed_bundles[@]}"; do
  requirement="$(codesign -dr - "${signed_bundle}" 2>&1)"
  leaf_sha1="$(sed -nE 's/.*certificate leaf = H"([[:xdigit:]]{40})".*/\1/p' <<<"${requirement}")"
  [[ "${leaf_sha1}" == "$(printf '%s' "${certificate_sha1}" | tr '[:upper:]' '[:lower:]')" ]] ||
    fail '签名指定要求没有锁定同一张专用证书'
  signing_details="$(codesign -dv --verbose=4 "${signed_bundle}" 2>&1)"
  grep -Fxq 'TeamIdentifier=not set' <<<"${signing_details}" ||
    fail '自签名产物不应带有 Apple Team ID'
done

printf '[开始] 制作并复核非公证 DMG\n'
mkdir -p "${staging_directory}" "${mount_point}"
ditto "${app_path}" "${staging_directory}/WidgetSharingPoC.app"
ln -s /Applications "${staging_directory}/Applications"
hdiutil create -ov -volname 'SSL 小组件共享验证' \
  -srcfolder "${staging_directory}" -format UDZO "${dmg_path}"
codesign --force --sign "${certificate_sha1}" --timestamp=none "${dmg_path}"
codesign --verify --verbose=2 "${dmg_path}"
hdiutil attach -readonly -nobrowse -mountpoint "${mount_point}" "${dmg_path}"
mounted=1
codesign --verify --deep --strict --verbose=2 "${mount_point}/WidgetSharingPoC.app"
[[ -d "${mount_point}/WidgetSharingPoC.app/Contents/PlugIns/WidgetSharingPoCWidget.appex" ]] ||
  fail 'DMG 内缺少 Widget 扩展'
if [[ "${diagnostic_without_helper}" == true ]]; then
  [[ ! -e "${mount_point}/WidgetSharingPoC.app/Contents/Helpers/WidgetSharingRepairHelper.app" ]] ||
    fail '诊断 DMG 内仍含升级修复助手'
else
  [[ -d "${mount_point}/WidgetSharingPoC.app/Contents/Helpers/WidgetSharingRepairHelper.app" ]] ||
    fail 'DMG 内缺少升级修复助手'
fi
hdiutil detach "${mount_point}"
mounted=0

(cd "${output_directory}" && shasum -a 256 widget-sharing-poc.dmg >SHA256SUMS)
if [[ "${diagnostic_without_helper}" == true ]]; then
  helper_status='未嵌入；仅供 Finder 覆盖诊断，先不要启动宿主'
  static_result='同证书签名、嵌入扩展、不含助手、签名权限、DMG 内签名和 SHA-256 均已核验'
  unverified='用户覆盖安装、原桌面组件位置、系统扩展登记与回执运行态'
else
  helper_status="已嵌入：${helper_identifier}"
  static_result='同证书签名、嵌入扩展与助手、构建号、签名权限、DMG 内签名和 SHA-256 均已核验'
  unverified='用户首次安装、助手旧扩展修复、受控替换命令实际运行、原桌面组件位置、系统小组件显示与新回执运行态'
fi
cat >"${report_path}" <<EOF
验证对象：SSL Widget 独立假数据 PoC
源码提交：${GITHUB_SHA:-未知}
无助手诊断开关：${diagnostic_without_helper}
宿主 Bundle ID：${app_identifier}
Widget Bundle ID：${widget_identifier}
修复助手：${helper_status}
共享目录：~${shared_path}
签名证书：${signing_identity}
叶证书 SHA-1 前 12 位：${certificate_sha1:0:12}
权限：宿主专用目录读写，Widget 仅 config/ 只读及 state/ 读写；宿主与 Widget 保留沙盒；无 App Group
静态结果：${static_result}
未验证：${unverified}
EOF
printf '[通过] 候选 DMG、静态报告及校验和位于 dist/\n'
