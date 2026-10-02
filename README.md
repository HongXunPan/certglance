# CertGlance

**Mac 桌面的 TLS 证书到期小组件。**

CertGlance 以系统桌面小组件为主要入口，优先展示最需要关注的域名、证书剩余天数与检查状态。宿主 App 只负责管理域名、主动检查和请求本地通知权限，不另造一套完整看板。

## 功能范围

- 小尺寸展示当前最需要关注的证书；中尺寸同时展示另外两个域名的状态。
- 使用系统 TLS 信任结果读取 HTTPS 证书到期时间，区分已过期、不受信任与检查失败，不把网络错误误报为健康。
- 现有源码包含默认 30／7／1 天本地提醒规则；实际通知投递仍待安装后验收。
- 不监控域名注册到期、网站可用率，也不自动续签证书。

## 项目状态

**开发中，暂无经过实机验收的稳定安装版。**工程可做无签名构建；正式签名、DMG、更新、安装后共享数据与通知投递尚未完成验收。小组件刷新由 macOS 调度，不能作为全天候生产告警的唯一渠道。

工程内部暂沿用 `SSLWidget` 名称及开发态 Bundle ID；它们不是已确定的正式分发身份。技术边界见 [工程代码技术选型](docs/工程代码技术选型.md)。

## 开发验证

在本目录运行：

```sh
plutil -lint SSLWidget.xcodeproj/project.pbxproj App/Info.plist Widget/Info.plist App/App.entitlements Widget/Widget.entitlements
xcrun swift format lint --recursive --strict App Widget Shared
xcodebuild -project SSLWidget.xcodeproj -scheme SSLWidget -destination 'platform=macOS' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build
xcrun swiftc -swift-version 6 -parse-as-library -module-cache-path .build/SwiftModuleCache -Xcc -fmodules-cache-path=.build/ClangModuleCache Shared/DomainModels.swift Shared/NotificationPolicy.swift Tests/ModelChecks.swift -o .build/ModelChecks && .build/ModelChecks
```

无签名构建仅证明源码和工程能编译，不能证明系统小组件注册、共享容器和通知投递可用。

## 签名文件共享实验

独立的 [WidgetKit 共享 PoC](PoC/WidgetSharing/README.md) 只使用假数据，验证自签名宿主与小组件能否访问同一专用文件；它不修改正式应用。手动 [GitHub Actions 工作流](.github/workflows/widget-sharing-poc.yml) 可打包候选 DMG，但须先配置项目专用签名 Secrets。源码提交、静态构建和 CI 打包均不代表安装后共享已通过验收，也不会自动发布正式版。

## 开源许可

本项目采用 [MIT 许可证](LICENSE)。
