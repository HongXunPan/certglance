# CertGlance

**Mac 桌面的 TLS 证书到期看板与小组件。**

CertGlance 在系统桌面小组件中快速呈现最需要关注的证书；宿主 App 提供多端点图形看板、管理、主动检查和本地通知授权。界面使用 macOS 原生 SwiftUI 组件与系统语义颜色。

## 功能范围

- 小尺寸展示当前最需要关注的证书，配对显示剩余天数与到期日期；中尺寸同时展示最多另外两个端点的状态与到期日期。
- 宿主看板以状态总览、到期圆环和端点卡片展示检查结果；可粘贴带路径的 HTTPS URL，也支持 `域名:端口`，同一域名的不同 HTTPS 端口独立监控。旧数据缺少端口时按 443 读取。
- 使用系统 TLS 信任结果读取 HTTPS 证书到期时间，区分已过期、不受信任与检查失败，不把网络错误误报为健康。
- 现有源码包含默认 30／7／1 天本地提醒规则；Widget 时间线预排天数变化、分批检查端点，实际运行仍受 macOS 调度与通知权限影响，本轮新构建的投递需重新验收。
- 不监控域名注册到期、网站可用率，也不自动续签证书。

## 项目状态

**此前构建 3 已在一台 Mac 上通过签名安装与基础功能实机验收；本轮看板和非 443 端口改动仍待新构建验收。**源码包含自签名文件桥接、真实 TLS 检查、默认 30／7／1 天提醒与小／中尺寸 Widget。手动 GitHub Actions 可生成非公证 DMG；CI 静态签名通过不等于新构建的小组件、跨进程文件共享或系统通知投递已在用户电脑上通过。小组件刷新由 macOS 调度，不能作为全天候生产告警的唯一渠道。

Xcode 工程与 scheme 沿用内部名称 `SSLWidget`，正式宿主 Bundle ID 为 `com.HongXunPan.CertGlance`，Widget Bundle ID 为 `com.HongXunPan.CertGlance.Widget`。技术边界见[工程代码技术选型](docs/工程代码技术选型.md)。

## 开发验证

在本目录运行：

```sh
bash scripts/check-certglance.sh
xcodebuild -project SSLWidget.xcodeproj -scheme SSLWidget -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

无签名构建仅证明源码和工程能编译，不能证明系统小组件注册、共享文件桥接和通知投递可用。父仓 `scripts/verify.sh` 另可做双架构与真实域名网络冒烟。

## 安装候选

手动工作流 [CertGlance 正式候选打包](.github/workflows/certglance.yml) 使用项目专用自签名证书生成双架构、非公证 DMG，不自动发布 Release。首次安装、系统安全提示、签名校验、运行态验收和已知升级限制见[正式候选验收](docs/正式候选验收.md)。不要把假数据 PoC DMG 当成正式 App，也不要用 Finder 拖拽覆盖已安装的旧版作为已支持升级方式。

## 签名文件共享实验

独立的 [WidgetKit 共享 PoC](PoC/WidgetSharing/README.md) 只使用假数据，曾验证自签名宿主与小组件能否访问同一专用文件。它保留为升级与共享诊断工程，与正式 CertGlance 的 Bundle ID、数据目录和打包工作流隔离；其运行态结果不能代替正式应用验收。

## 开源许可

本项目采用 [MIT 许可证](LICENSE)。
