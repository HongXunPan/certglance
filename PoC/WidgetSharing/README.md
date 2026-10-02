# WidgetKit 自签名专用文件 PoC

此独立工程只使用假数据验证专用文件桥接，不使用 App Group，不读取真实域名或证书，也不修改正式 SSL 证书看板。版本 2 的“宿主写入、Widget 读取”与版本 3 的“宿主写请求、Widget 写回执、宿主回读”均已由用户在自签名安装后验收。版本 3→4、4→5 拖拽覆盖时，磁盘上的宿主与包内扩展已经升级，但旧扩展进程仍处理新请求；仅请求时间线刷新未使扩展代码更新。定点结束旧扩展进程后，新请求回执和桌面小组件才恢复到新构建。版本 6 尝试把该定点修复放到首次启动自动执行；前两次实测不代表所有机器都会如此，也不证明版本 6 或正式应用的升级链路已通过。

## 验证入口

- 在父工作区运行 `bash scripts/verify-widget-sharing-poc.sh`：检查 plist、宿主根目录读写／Widget `config/` 只读与 `state/` 读写权限、Swift 格式并无签名构建。临时产物由脚本放在父仓 `.codex-tmp/`，退出时清理。
- 仅检出开源子仓时，可在子仓根目录执行：

```sh
plutil -lint PoC/WidgetSharing/WidgetSharingPoC.xcodeproj/project.pbxproj \
  PoC/WidgetSharing/App/Info.plist PoC/WidgetSharing/Widget/Info.plist \
  PoC/WidgetSharing/Helper/Info.plist \
  PoC/WidgetSharing/App/App.entitlements PoC/WidgetSharing/Widget/Widget.entitlements
xcrun swift format lint --recursive --strict \
  PoC/WidgetSharing/App PoC/WidgetSharing/Widget PoC/WidgetSharing/Shared \
  PoC/WidgetSharing/Helper
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

工作流使用 macOS 26 Runner 无签名构建，再将证书导入临时钥匙串。脚本仅允许在 GitHub 托管 Runner 运行；导入管理员域信任设置前先核对固定指纹，只为该证书增加代码签名用途的信任，并为非交互导入设置 45 秒上限。此设置只作用于本次临时 Runner，不修改本机授权数据库。随后按 Widget → 独立修复助手 → 宿主顺序签名，核对三者的 Bundle ID、构建号、专用证书、宿主及 Widget 沙盒、助手非沙盒、分目录权限和 DMG 内嵌结构。助手仅在确认同一请求由旧版扩展处理时启动，不在后台常驻。产物为 3 天保留的 Artifact，包含 `widget-sharing-poc.dmg`、`widget-sharing-poc-verification.txt` 与 `SHA256SUMS`。解压 Artifact 后，在其目录运行 `shasum -a 256 -c SHA256SUMS` 核对下载文件。静态核验通过只能证明签名和包结构，不能证明助手能在用户机器上启动、系统会注册组件或允许跨进程读写。

## 已完成的版本 3 文件桥接验收

前提：macOS 26、已完成的同一次工作流 Artifact；宿主和 Widget 必须使用同一张 SSL Widget 专用证书，不得复用 Mihomo Meter 的证书。先核对 `SHA256SUMS` 与 DMG，再安装。因未公证，首次打开如被系统拦截，应从“系统设置 → 隐私与安全性”选择“仍要打开”；不要全局关闭 Gatekeeper。

1. 用同一身份签名两个 target，安装完整的版本 3 `WidgetSharingPoC.app`。打开宿主，点击“写入新假请求”，记录请求标记、目录标识和位置。宿主会请求 WidgetKit 刷新，但不保证立即执行。
2. 在系统小组件图库添加“SSL 共享验证”。确认页脚为“仅假数据 · 版本 3”；等待真实时间线运行后，记录小组件的状态、请求标记、回执标记和目录标识。图库快照只读，不会写回执；若仍显示旧版本，可手动移除后重新添加，并核对已安装 App 与扩展版本。
3. 回到宿主点击“读取组件回执”。**通过条件**：Widget 显示“组件写回成功”；宿主显示“回执匹配”；两端请求标记一致、回执标记一致、目录标识一致，且宿主位置为账户主目录。任一项缺失都不算通过。
4. 再写入一个新请求并主动回读。旧回执应显示“回执属于旧请求”或“等待组件回执”，不能误报匹配；待 Widget 新时间线运行后，再手动读取并按第 3 步核对新请求。此步骤不以等待时长作断言。

目录标识是目录路径的短指纹，同一账户与路径下保持不变；每次点击写入后变化的是 8 位请求标记。Widget 对每个新请求生成一个 8 位回执标记，同一请求的后续时间线复用该回执，避免核对时标记跳变。小组件优先展示状态、回执与请求；路径位置在宿主结果和组件辅助功能文本中可见。

## 版本 4 启动升级检查（已完成单次实机排障）

1. 保留已经放置的版本 3 小组件，退出宿主，从新候选 DMG 拖拽版本 4 到 `/Applications` 并确认替换。不要先移除小组件，也不要手动结束扩展进程；随后只从 `/Applications/WidgetSharingPoC.app` 启动新宿主。
2. 首次启动应自动生成新的假请求，并显示“启动升级检查（构建 4）”、请求标记及“已请求系统刷新组件”。包内扩展构建与宿主不一致时应显示错误，不应把该次启动当成 WidgetKit 刷新成功。普通重复启动同一构建不应再次自动生成请求；“写入新假请求”按钮仍可手动使用。
3. 等待小组件时间线实际运行，再点击宿主“读取组件回执”。**通过条件**：宿主显示“回执匹配”，当前进程构建与回执构建均为 `4`，请求标记对应本次启动请求，桌面小组件页脚为“仅假数据 · 版本 4”。若同一请求得到“组件版本不匹配”且回执构建为“未提供”，表示旧版扩展仍处理了请求；若仍是“等待组件回执”或“回执属于旧请求”，只能说明尚无本次请求的有效回执，不能据此断言旧进程驻留。
4. 此次实测确认，磁盘上的宿主和包内扩展都是构建 4，但同一新请求仍由版本 3 旧进程处理，桌面小组件不变。用户授权后只向该旧扩展进程发送 `TERM`；随后新请求的回执构建为 `4`，桌面小组件也恢复。每次升级仍须分别记录安装构建、回执构建和桌面结果；静态构建、图库预览或单次 `reloadTimelines` 调用不能代替运行态结论。

启动检查只在宿主首次运行某构建时发起一次时间线刷新请求，不等待系统调度，不自动重试、不终止 Widget 扩展或系统进程。回执随构建号变化而重写：新扩展即使遇到旧扩展留下的同请求回执，也会写入自己的构建号。版本 4 的拖拽实测已证明，正常刷新不能保证旧扩展进程被替换。

## 版本 5 拖拽升级与定点修复对照（已完成单次实机验收）

版本 5 只递增宿主与 Widget 构建号，并将小组件页脚改为读取扩展进程的实际构建号；保持 Bundle ID、Widget kind、文件格式和 DMG 拖拽安装入口不变。父仓的 `scripts/repair-widget-sharing-poc.sh` 是本机 PoC 工具，不进入候选 DMG，也不是正式应用的自动升级机制。

1. 从同一签名身份生成版本 5 候选 DMG，核对 `SHA256SUMS`。保留已经放置的版本 4 小组件，退出宿主，按原方式拖拽覆盖 `/Applications/WidgetSharingPoC.app`；不要先运行修复脚本，也不要移除小组件。
2. 启动 `/Applications` 中的新宿主，记录自动生成的请求标记。等组件实际执行时间线后，点击“读取组件回执”。若同一请求的回执构建为 `5`、状态“回执匹配”且桌面页脚为“仅假数据 · 版本 5”，记录为本次拖拽直接成功，不运行修复脚本。
3. 只有在同一请求的回执明确显示构建 `4` 或“未提供”，且桌面仍是旧版时，先在**父仓根目录的普通终端**执行 `bash scripts/repair-widget-sharing-poc.sh 5` 只读预检。确认脚本识别的是已安装构建 5、项目专用签名和当前账户的本项目 Widget 进程后，再人工执行 `bash scripts/repair-widget-sharing-poc.sh 5 --apply`。脚本只向这个精确进程发送 `TERM`，不会更新、删除或重装 App，也不操作系统守护进程；若预检失败或无匹配进程，停止并记录结果，不改用宽泛 `killall`。
4. 再从 `/Applications` 打开宿主，点击“写入新假请求”，等待 WidgetKit 实际运行并读取回执。**修复通过条件**：新请求回执构建为 `5`、状态“回执匹配”、桌面页脚为版本 5，且原有小组件位置与配置未丢失。脚本成功发送信号不等于上述通过；若仍不匹配，保留现状并报告，不自动重试或移除小组件。

本轮实测中，启动检查写入请求 `BE89A41B` 后，旧扩展给该请求写回构建 `4`，桌面仍显示版本 4；父仓脚本核对安装包、专用签名和当前用户精确扩展进程后，只对该进程发送 `TERM`。后续新请求回执和桌面小组件均恢复为版本 5，用户确认“可以了”。这只证明当前机器上的一次定点修复，不能视为普通用户可用的自动流程。

## 版本 6 首次启动自动修复（待签名包与实机验收）

版本 6 保留原 DMG 拖拽安装入口，宿主和 Widget 仍在沙盒内。新增一个嵌入宿主的短时后台助手应用；它不使用沙盒，只拥有当前用户权限，不请求管理员授权，不常驻，也不进入正式证书看板。只有新版宿主收到**同一请求的旧版扩展回执**时才会启动助手；无回执、回执构建已正确或请求被改写时都不处理进程。助手再次核对当前请求与回执、三者构建号、固定项目专用证书、当前用户和精确的本项目扩展可执行路径；最多对一个匹配进程发送 `TERM`，不处理其他 App 或系统守护进程。宿主随后写入新请求、请求 WidgetKit 刷新，并等候新回执。每个构建自动尝试至多一次，失败或超时只显示状态和“重新检查升级”按钮，不删除数据、不自动反复终止进程。

验收时保留版本 5 桌面小组件，退出旧宿主后拖拽覆盖版本 6，再从 `/Applications` 首次打开新版宿主。分别记录安装包内宿主、Widget、助手的构建号，首次请求与回执构建、是否出现系统安全提示、助手是否实际退出旧进程、二次请求与回执构建，以及桌面页脚是否变为版本 6。**通过条件**是无终端操作、无手动移除小组件、无需点击修复按钮，二次请求回执与桌面页脚均为版本 6；只看到“已启动助手”或“已请求刷新”不算通过。如果助手被 Gatekeeper 或沙盒边界阻断，保留旧组件和数据，记录提示并停止，不全局关闭安全机制或改用宽泛 `killall`。

构建失败先查工程和 SDK；宿主写入失败先查根目录权限；Widget 不出现先查嵌入、签名和系统注册；“请求读取失败”先查 `config/` 只读例外；“回执写入失败”先查 `state/` 读写例外及目录是否由宿主创建；“回执属于旧请求”先查当前 Widget 时间线是否执行。诊断界面仅展示短目录标识、标记与错误域／错误码，不展示完整路径或系统日志。系统日志没有拒绝记录也不能单独证明授权成功。

## 边界与清理

专用目录为当前账户下 `Library/Application Support/com.HongXunPan.SSLWidget.WidgetSharingPoC/`。宿主读写此根目录，并创建 `config/request.txt` 与 `state/`；Widget 只读 `config/`，只在生成时间线时读写 `state/receipt.json`。目录权限为 `0700`，文件为 `0600`，但不能隔离同一用户下的其他进程。旧版 `probe.txt` 不参与本轮验证。所用沙盒临时文件例外尚不能视为稳定的正式共享能力；此 PoC 不验证并发写入、通知、证书检查或正式应用更新链路。验收结束后退出 PoC App，可手动删除该**仅含假数据**的专用目录。正式项目仍使用开发态 App Group 仓储，是否迁移需要另行确认。
