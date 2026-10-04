# 参与 CertGlance

感谢参与。CertGlance 是面向 macOS 26 起的原生 TLS 证书到期看板；项目仍处于正式候选阶段，不应把构建通过视为 WidgetKit 或通知已在所有设备上验收。

## 提交问题与建议

- 使用仓库的缺陷或功能建议表单。缺陷请附 macOS 版本、芯片架构、App 构建号、复现步骤、预期与实际结果。
- **安全漏洞不要提交公开 Issue**；请按 [安全策略](SECURITY.md)私密报告。
- 提交截图、日志或配置前，请去除真实域名、账户路径、证书内容、通知标识及其他私人资料。可用 `example.com` 或可控测试端点重现。
- 小组件刷新时刻由系统决定。报告刷新问题时，请区分图库预览、桌面实例、宿主 App 与真实时间线的观察结果。

## 开发与验证

1. 在具备 macOS 26 SDK 的 Mac 上检出本仓库。工程不使用第三方运行时依赖；Xcode 工程入口为 `SSLWidget.xcodeproj`。
2. 优先阅读 [工程代码技术选型](docs/工程代码技术选型.md)，确认 App、Widget、共享文件与通知的边界。独立 `PoC/` 只承载假数据实验，不代表正式产品行为。
3. 在仓库根目录运行：

   ```sh
   bash scripts/check-certglance.sh
   xcodebuild -project SSLWidget.xcodeproj -scheme SSLWidget \
     -destination 'generic/platform=macOS' -derivedDataPath .build/DerivedData \
     CODE_SIGNING_ALLOWED=NO build
   ```

4. 改动界面时，运行 `bash scripts/render-visual-previews.sh` 并检查浅色、深色和长域名等假数据预览。离屏预览不能替代桌面小组件、键盘与 VoiceOver 实机验收。

无签名构建不能验证自签名文件桥接、系统注册或通知投递。不要在贡献分支运行正式签名打包脚本，也不要索取、复制或提交仓库签名证书与 Secrets。完整候选验收边界见[正式候选验收](docs/正式候选验收.md)。

## Pull Request 约定

- 每个 PR 聚焦一个问题，说明动机、影响范围、验证层级及未完成的实机验收；行为变更应同时更新相应测试和文档。
- 保持 App、Widget 与 PoC 的职责隔离；不得在本仓库加入父工作区私有脚本、真实用户数据、签名私钥、P12 或本机绝对路径。
- 本项目优先使用系统 SwiftUI、WidgetKit 和 SF Symbols。涉及原生交互或系统行为的改动应说明所用系统语义，不用自绘控件代替已有原生能力。
- PR 自动检查只做无签名验证。正式 DMG 仍需维护者从 `main` 手动触发独立工作流，并按实际安装层级验收。

参与讨论请遵守[社区行为准则](CODE_OF_CONDUCT.md)。
