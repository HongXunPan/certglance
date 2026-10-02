# WidgetKit 自签名专用文件 PoC

此独立工程只验证“宿主写入、Widget 读取同一个用户目录文件”。它不使用 App Group，不读取真实域名或证书，也不修改正式 SSL 证书看板的数据。当前完成了结构检查与**无签名构建**，已加入签名打包工作流源码；自签名安装后的 WidgetKit 注册、目录访问与刷新仍待实机验收。

## 验证入口

- 在父工作区运行 `bash scripts/verify-widget-sharing-poc.sh`：检查 plist、宿主读写／Widget 只读权限、Swift 格式并无签名构建。临时产物由脚本放在父仓 `.codex-tmp/`，退出时清理。
- 仅检出开源子仓时，可在子仓根目录执行：

```sh
plutil -lint PoC/WidgetSharing/WidgetSharingPoC.xcodeproj/project.pbxproj \
  PoC/WidgetSharing/App/Info.plist PoC/WidgetSharing/Widget/Info.plist \
  PoC/WidgetSharing/App/App.entitlements PoC/WidgetSharing/Widget/Widget.entitlements
xcrun swift format lint --recursive --strict \
  PoC/WidgetSharing/App PoC/WidgetSharing/Widget PoC/WidgetSharing/Shared
xcodebuild -project PoC/WidgetSharing/WidgetSharingPoC.xcodeproj \
  -scheme WidgetSharingPoC -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath .build/WidgetSharingPoC CODE_SIGNING_ALLOWED=NO build
```

这些检查不需要 Apple Developer Program，但**不能**代替签名安装后的运行态结果。

## GitHub Actions 候选 DMG

手动工作流入口为 `.github/workflows/widget-sharing-poc.yml`，仅允许在 `main` 分支运行；它不创建 GitHub Release，也不修改正式应用。首次运行前，须在 SSL Widget 开源仓库单独配置以下值，不能直接读取 Mihomo Meter 仓库级 Secrets：

- Actions Secret `SSL_WIDGET_SIGNING_P12_BASE64`：**SSL Widget 专用**代码签名证书及私钥导出的 P12，经 Base64 编码后的内容。
- Actions Secret `SSL_WIDGET_SIGNING_P12_PASSWORD`：该 P12 的导出密码。
- Actions Variable `SSL_WIDGET_SIGNING_CERT_SHA1`：同一证书的 40 位 SHA-1 指纹，用于拒绝意外换证书；这是公开指纹，不是私钥。

证书显示名称固定为 `SSL Widget By HongXunPan`。只创建一次并离线保存受控备份；不得复用 `Mihomo Meter By HongXunPan`，也不得把 P12、密码、私钥或真实域名数据提交进仓库。配置 Secrets 与触发工作流都属于后续独立步骤。

工作流使用 macOS 26 Runner 无签名构建，再将证书导入临时钥匙串。脚本仅允许在 GitHub 托管 Runner 运行；导入管理员域信任设置前先核对固定指纹，只为该证书增加代码签名用途的信任，并为非交互导入设置 45 秒上限。此设置只作用于本次临时 Runner，不修改本机授权数据库。随后按 Widget → 宿主顺序签名，核对 Bundle ID、沙盒、专用目录权限和 DMG 内嵌扩展。产物为 3 天保留的 Artifact，包含 `widget-sharing-poc.dmg`、`widget-sharing-poc-verification.txt` 与 `SHA256SUMS`。解压 Artifact 后，在其目录运行 `shasum -a 256 -c SHA256SUMS` 核对下载文件。静态核验通过只能证明签名和包结构，不能证明系统会注册组件或允许跨进程读取。

## 自签名实机验收

前提：macOS 26、已完成的同一次工作流 Artifact；宿主和 Widget 必须使用同一张 SSL Widget 专用证书，不得复用 Mihomo Meter 的证书。先核对 `SHA256SUMS` 与 DMG，再安装。因未公证，首次打开如被系统拦截，应从“系统设置 → 隐私与安全性”选择“仍要打开”；不要全局关闭 Gatekeeper。

1. 使用同一身份签名两个 target，安装完整的 `WidgetSharingPoC.app`，打开宿主并点击“写入新假标记”。记录界面显示的目录标识、标记和写入／回读状态。
2. 在系统小组件图库添加“SSL 共享验证”。确认它显示“仅假数据 · 版本 1”，并记录目录标识、标记及读取状态。若显示旧时间线，可手动移除后重新添加一次。
3. **通过条件**：宿主写入和回读成功；Widget 确实出现在系统图库；两端均指向账户主目录、目录标识一致，Widget 读取到与宿主相同的最新标记。缺任何一项均不得视为通过。

构建失败先查工程和 SDK；宿主写入失败先查目录权限；Widget 不出现先查嵌入、签名和系统注册；Widget 读取失败先查其只读权限；标记不一致先查是否仍显示旧时间线。诊断界面仅展示短目录标识、标记与错误域／错误码，不展示完整路径或系统日志。系统日志没有拒绝记录也不能单独证明授权成功。

## 边界与清理

专用目录为当前账户下 `Library/Application Support/com.HongXunPan.SSLWidget.WidgetSharingPoC/`，只允许放假标记。所用沙盒临时文件例外尚不能视为稳定的正式共享能力；`0700/0600` 也不能隔离同一用户下的其他进程。此 PoC 不验证通知、证书检查或正式更新链路。验收结束后退出 PoC App，可手动删除该**仅含假数据**的专用目录。正式项目仍使用开发态 App Group 仓储，是否迁移必须等待此 PoC 的运行态结论与后续确认。
